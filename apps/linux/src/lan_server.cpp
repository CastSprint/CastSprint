#include "lan_server.hpp"
#include "log.hpp"

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <chrono>

namespace castsprint::linux_app {

LanServer::LanServer() = default;

LanServer::~LanServer() {
    Stop();
}

bool LanServer::Start(uint16_t port, LanCallbacks callbacks) {
    if (isRunning_.load()) return true;

    port_ = port;
    callbacks_ = std::move(callbacks);

    listenSock_ = socket(AF_INET, SOCK_STREAM, 0);
    if (listenSock_ < 0) {
        Log(LogLevel::Error, "socket() failed");
        return false;
    }

    int opt = 1;
    setsockopt(listenSock_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in serverAddr{};
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons(port);
    serverAddr.sin_addr.s_addr = INADDR_ANY;

    if (bind(listenSock_, reinterpret_cast<sockaddr*>(&serverAddr), sizeof(serverAddr)) < 0) {
        Log(LogLevel::Error, "bind() failed on port " + std::to_string(port));
        close(listenSock_);
        listenSock_ = -1;
        return false;
    }

    if (listen(listenSock_, 16) < 0) {
        Log(LogLevel::Error, "listen() failed");
        close(listenSock_);
        listenSock_ = -1;
        return false;
    }

    isRunning_.store(true);
    sessionManager_.SetState(session::ConnectionState::Listening);
    if (callbacks_.onStateChanged) callbacks_.onStateChanged(session::ConnectionState::Listening);

    acceptThread_ = std::thread(&LanServer::ServerAcceptLoop, this);
    Log(LogLevel::Info, "LAN Receiver listening on port " + std::to_string(port));
    return true;
}

void LanServer::Stop() {
    if (!isRunning_.load()) return;
    isRunning_.store(false);

    if (listenSock_ >= 0) {
        shutdown(listenSock_, SHUT_RDWR);
        close(listenSock_);
        listenSock_ = -1;
    }

    if (activeClientSock_ >= 0) {
        shutdown(activeClientSock_, SHUT_RDWR);
        close(activeClientSock_);
        activeClientSock_ = -1;
    }

    if (acceptThread_.joinable()) {
        acceptThread_.join();
    }
    if (clientThread_.joinable()) {
        clientThread_.join();
    }

    sessionManager_.SetState(session::ConnectionState::Closed);
    if (callbacks_.onStateChanged) callbacks_.onStateChanged(session::ConnectionState::Closed);
}

void LanServer::ServerAcceptLoop() {
    while (isRunning_.load()) {
        sockaddr_in clientAddr{};
        socklen_t clientLen = sizeof(clientAddr);
        int clientSock = accept(listenSock_, reinterpret_cast<sockaddr*>(&clientAddr), &clientLen);

        if (!isRunning_.load()) {
            if (clientSock >= 0) close(clientSock);
            break;
        }

        if (clientSock < 0) continue;

        char clientIpStr[INET_ADDRSTRLEN]{};
        inet_ntop(AF_INET, &clientAddr.sin_addr, clientIpStr, sizeof(clientIpStr));
        Log(LogLevel::Info, "Client connected from " + std::string(clientIpStr));

        sessionManager_.SetState(session::ConnectionState::Handshaking);
        if (callbacks_.onStateChanged) callbacks_.onStateChanged(session::ConnectionState::Handshaking);

        activeClientSock_ = clientSock;
        HandleClient(clientSock);

        close(clientSock);
        activeClientSock_ = -1;

        if (isRunning_.load()) {
            sessionManager_.SetState(session::ConnectionState::Listening);
            if (callbacks_.onStateChanged) callbacks_.onStateChanged(session::ConnectionState::Listening);
        }
    }
}

void LanServer::HandleClient(int clientSock) {
    int opt = 1;
    setsockopt(clientSock, IPPROTO_TCP, TCP_NODELAY, &opt, sizeof(opt));
    int bufSize = 1024 * 1024;
    setsockopt(clientSock, SOL_SOCKET, SO_RCVBUF, &bufSize, sizeof(bufSize));

    std::vector<uint8_t> rxBuffer;
    rxBuffer.reserve(protocol::kMaxPayloadSize + protocol::kHeaderSize);
    std::vector<uint8_t> readChunk(64 * 1024);

    bool authenticated = false;

    while (isRunning_.load()) {
        ssize_t bytesRead = recv(clientSock, readChunk.data(), readChunk.size(), 0);
        if (bytesRead <= 0) break;

        rxBuffer.insert(rxBuffer.end(), readChunk.begin(), readChunk.begin() + bytesRead);

        while (rxBuffer.size() >= protocol::kHeaderSize) {
            protocol::Header hdr{};
            if (protocol::DecodeHeader(rxBuffer, hdr) != protocol::DecodeError::None) {
                Log(LogLevel::Error, "Malformed protocol header; closing connection");
                return;
            }

            const size_t totalMsgSize = protocol::kHeaderSize + hdr.payloadLength;
            if (rxBuffer.size() < totalMsgSize) {
                break;
            }

            protocol::Message msg{};
            size_t consumed = 0;
            auto err = protocol::DecodeMessage(rxBuffer, msg, consumed);
            if (err != protocol::DecodeError::None) {
                Log(LogLevel::Error, "DecodeMessage failed: " + std::string(protocol::ToString(err)));
                return;
            }

            rxBuffer.erase(rxBuffer.begin(), rxBuffer.begin() + consumed);

            if (std::holds_alternative<protocol::Hello>(msg.payload)) {
                const auto& hello = std::get<protocol::Hello>(msg.payload);
                Log(LogLevel::Info, "Received Hello from device: " + hello.deviceName + " (" + hello.deviceModel + ")");

                auto [ack, isAccepted] = sessionManager_.ProcessHello(hello, hello.deviceName);
                std::vector<uint8_t> ackBytes;
                protocol::EncodeMessage(ack.assignedSessionId, 1, ack, ackBytes);
                send(clientSock, ackBytes.data(), ackBytes.size(), 0);

                if (!isAccepted) {
                    Log(LogLevel::Error, "Hello authentication rejected: session PIN mismatch");
                    return;
                }
                authenticated = true;
                if (callbacks_.onStateChanged) callbacks_.onStateChanged(session::ConnectionState::Connected);
            } else if (!authenticated) {
                Log(LogLevel::Error, "Unauthenticated packet received before Hello; dropping connection");
                return;
            } else if (std::holds_alternative<protocol::VideoConfig>(msg.payload)) {
                const auto& vc = std::get<protocol::VideoConfig>(msg.payload);
                if (callbacks_.onVideoConfig) callbacks_.onVideoConfig(vc);
            } else if (std::holds_alternative<protocol::VideoFrame>(msg.payload)) {
                const auto& vf = std::get<protocol::VideoFrame>(msg.payload);
                sessionManager_.OnVideoFrameReceived(static_cast<uint32_t>(vf.data.size()),
                                                     (vf.frameFlags & protocol::kFrameKeyframe) != 0);
                if (callbacks_.onVideoFrame) callbacks_.onVideoFrame(vf);
            } else if (std::holds_alternative<protocol::AudioConfig>(msg.payload)) {
                const auto& ac = std::get<protocol::AudioConfig>(msg.payload);
                if (callbacks_.onAudioConfig) callbacks_.onAudioConfig(ac);
            } else if (std::holds_alternative<protocol::AudioFrame>(msg.payload)) {
                const auto& af = std::get<protocol::AudioFrame>(msg.payload);
                sessionManager_.OnAudioFrameReceived(static_cast<uint32_t>(af.data.size()));
                if (callbacks_.onAudioFrame) callbacks_.onAudioFrame(af);
            } else if (std::holds_alternative<protocol::Heartbeat>(msg.payload)) {
                const auto& hb = std::get<protocol::Heartbeat>(msg.payload);
                protocol::Heartbeat echoHb = hb;
                echoHb.echoTimestampMicros = hb.timestampMicros;
                echoHb.timestampMicros = static_cast<uint64_t>(
                    std::chrono::duration_cast<std::chrono::microseconds>(
                        std::chrono::steady_clock::now().time_since_epoch()).count());

                std::vector<uint8_t> echoBytes;
                protocol::EncodeMessage(msg.header.sessionId, msg.header.sequence + 1, echoHb, echoBytes);
                send(clientSock, echoBytes.data(), echoBytes.size(), 0);
            } else if (std::holds_alternative<protocol::Disconnect>(msg.payload)) {
                Log(LogLevel::Info, "Client requested disconnect");
                return;
            }
        }
    }
}

} // namespace castsprint::linux_app
