#include "lan_server.hpp"
#include "log.hpp"

#include <chrono>
#include <iomanip>
#include <sstream>

namespace castsprint::windows {

LanServer::LanServer() = default;

LanServer::~LanServer() {
    Stop();
}

bool LanServer::GenerateSelfSignedCert() {
    // Acquire Cryptographic Provider context
    if (!CryptAcquireContextW(&hCryptProv_, L"CastSprintKeyContainer", MS_ENH_RSA_AES_PROV_W,
                             PROV_RSA_AES, CRYPT_MACHINE_KEYSET)) {
        if (!CryptAcquireContextW(&hCryptProv_, L"CastSprintKeyContainer", MS_ENH_RSA_AES_PROV_W,
                                 PROV_RSA_AES, CRYPT_NEWKEYSET | CRYPT_MACHINE_KEYSET)) {
            // Fallback without machine keyset
            if (!CryptAcquireContextW(&hCryptProv_, nullptr, MS_ENH_RSA_AES_PROV_W,
                                     PROV_RSA_AES, CRYPT_VERIFYCONTEXT)) {
                log::Error("lan", "CryptAcquireContext failed");
                return false;
            }
        }
    }

    // Generate Key Pair
    HCRYPTKEY hKey = 0;
    if (!CryptGenKey(hCryptProv_, AT_KEYEXCHANGE, (2048 << 16) | CRYPT_EXPORTABLE, &hKey)) {
        log::Error("lan", "CryptGenKey failed");
        return false;
    }
    CryptDestroyKey(hKey);

    // Self-signed certificate subject name: CN=CastSprint Receiver
    CERT_NAME_BLOB subjectName{};
    BYTE pbEncoded[256];
    DWORD cbEncoded = sizeof(pbEncoded);
    if (!CertStrToNameW(X509_ASN_ENCODING, L"CN=CastSprint Receiver", CERT_X500_NAME_STR,
                        nullptr, pbEncoded, &cbEncoded, nullptr)) {
        log::Error("lan", "CertStrToName failed");
        return false;
    }
    subjectName.pbData = pbEncoded;
    subjectName.cbData = cbEncoded;

    CRYPT_KEY_PROV_INFO provInfo{};
    provInfo.pwszContainerName = const_cast<LPWSTR>(L"CastSprintKeyContainer");
    provInfo.pwszProvName = const_cast<LPWSTR>(MS_ENH_RSA_AES_PROV_W);
    provInfo.dwProvType = PROV_RSA_AES;
    provInfo.dwKeySpec = AT_KEYEXCHANGE;

    CRYPT_ALGORITHM_IDENTIFIER sigAlg{};
    sigAlg.pszObjId = const_cast<LPSTR>(szOID_RSA_SHA256RSA);

    SYSTEMTIME stStart, stEnd;
    GetSystemTime(&stStart);
    stEnd = stStart;
    stEnd.wYear += 2; // Valid for 2 years

    certContext_ = CertCreateSelfSignCertificate(hCryptProv_, &subjectName, 0, &provInfo,
                                                &sigAlg, &stStart, &stEnd, nullptr);
    if (!certContext_) {
        log::Error("lan", "CertCreateSelfSignCertificate failed");
        return false;
    }

    // Compute SHA-256 certificate fingerprint
    BYTE sha256[32];
    DWORD sha256Len = sizeof(sha256);
    if (!CryptHashCertificate(0, CALG_SHA_256, 0, certContext_->pbCertEncoded,
                             certContext_->cbCertEncoded, sha256, &sha256Len)) {
        log::Error("lan", "CryptHashCertificate failed");
        return false;
    }

    std::ostringstream ss;
    for (DWORD i = 0; i < sha256Len; ++i) {
        ss << std::hex << std::setw(2) << std::setfill('0') << std::uppercase << static_cast<int>(sha256[i]);
    }
    certFingerprintHex_ = ss.str();

    // Acquire SChannel Server Credentials
    SCHANNEL_CRED schannelCred{};
    schannelCred.dwVersion = SCHANNEL_CRED_VERSION;
    schannelCred.cCreds = 1;
    schannelCred.paCred = &certContext_;
    schannelCred.grbitEnabledProtocols = SP_PROT_TLS1_2_SERVER | SP_PROT_TLS1_3_SERVER;

    TimeStamp tsExpiry{};
    SECURITY_STATUS ssStatus = AcquireCredentialsHandleW(
        nullptr, const_cast<LPWSTR>(UNISP_NAME_W), SECPKG_CRED_INBOUND, nullptr,
        &schannelCred, nullptr, nullptr, &hServerCred_, &tsExpiry);

    if (ssStatus != SEC_E_OK) {
        log::Error("lan", "AcquireCredentialsHandle failed: " + std::to_string(ssStatus));
        return false;
    }
    hasCredHandle_ = true;

    sessionManager_.InitializePairing(certFingerprintHex_);
    log::Info("lan", "Self-signed certificate generated. SHA-256 Fingerprint: " + certFingerprintHex_);
    return true;
}

void LanServer::CleanupCert() {
    if (hasCredHandle_) {
        FreeCredentialsHandle(&hServerCred_);
        hasCredHandle_ = false;
    }
    if (certContext_) {
        CertFreeCertificateContext(certContext_);
        certContext_ = nullptr;
    }
    if (hCryptProv_) {
        CryptReleaseContext(hCryptProv_, 0);
        hCryptProv_ = 0;
    }
}

std::string LanServer::PairingUri(std::string_view localIp) const {
    std::ostringstream ss;
    ss << "castsprint://connect?host=" << localIp
       << "&port=" << port_
       << "&fp=" << certFingerprintHex_
       << "&token=" << sessionManager_.SessionPin()
       << "&name=Windows%20PC";
    return ss.str();
}

bool LanServer::Start(uint16_t port, LanCallbacks callbacks) {
    if (isRunning_.load()) return true;

    port_ = port;
    callbacks_ = std::move(callbacks);

    WSADATA wsaData{};
    int res = WSAStartup(MAKEWORD(2, 2), &wsaData);
    if (res != 0) {
        log::Error("lan", "WSAStartup failed");
        return false;
    }

    if (!GenerateSelfSignedCert()) {
        log::Error("lan", "Failed to initialize TLS certificate and credentials");
        WSACleanup();
        return false;
    }

    listenSocket_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listenSocket_ == INVALID_SOCKET) {
        log::Error("lan", "socket() failed");
        CleanupCert();
        WSACleanup();
        return false;
    }

    int opt = 1;
    setsockopt(listenSocket_, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&opt), sizeof(opt));

    sockaddr_in serverAddr{};
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = htonl(INADDR_ANY);
    serverAddr.sin_port = htons(port);

    if (bind(listenSocket_, reinterpret_cast<sockaddr*>(&serverAddr), sizeof(serverAddr)) == SOCKET_ERROR) {
        log::Error("lan", "bind() failed on port " + std::to_string(port));
        closesocket(listenSocket_);
        listenSocket_ = INVALID_SOCKET;
        CleanupCert();
        WSACleanup();
        return false;
    }

    if (listen(listenSocket_, SOMAXCONN) == SOCKET_ERROR) {
        log::Error("lan", "listen() failed");
        closesocket(listenSocket_);
        listenSocket_ = INVALID_SOCKET;
        CleanupCert();
        WSACleanup();
        return false;
    }

    isRunning_.store(true);
    sessionManager_.SetState(session::ConnectionState::Listening);
    if (callbacks_.onStateChanged) callbacks_.onStateChanged(session::ConnectionState::Listening);

    serverThread_ = std::thread(&LanServer::ServerAcceptLoop, this);
    log::Info("lan", "LAN Receiver listening on port " + std::to_string(port));
    return true;
}

void LanServer::Stop() {
    if (!isRunning_.load()) return;
    isRunning_.store(false);

    if (listenSocket_ != INVALID_SOCKET) {
        closesocket(listenSocket_);
        listenSocket_ = INVALID_SOCKET;
    }

    if (serverThread_.joinable()) {
        serverThread_.join();
    }

    CleanupCert();
    WSACleanup();

    sessionManager_.SetState(session::ConnectionState::Closed);
    if (callbacks_.onStateChanged) callbacks_.onStateChanged(session::ConnectionState::Closed);
}

void LanServer::ServerAcceptLoop() {
    while (isRunning_.load()) {
        sockaddr_in clientAddr{};
        int clientLen = sizeof(clientAddr);
        SOCKET clientSock = accept(listenSocket_, reinterpret_cast<sockaddr*>(&clientAddr), &clientLen);

        if (!isRunning_.load()) {
            if (clientSock != INVALID_SOCKET) closesocket(clientSock);
            break;
        }

        if (clientSock == INVALID_SOCKET) continue;

        char clientIpStr[INET_ADDRSTRLEN]{};
        inet_ntop(AF_INET, &clientAddr.sin_addr, clientIpStr, sizeof(clientIpStr));
        log::Info("lan", "Client connected from " + std::string(clientIpStr));

        sessionManager_.SetState(session::ConnectionState::Handshaking);
        if (callbacks_.onStateChanged) callbacks_.onStateChanged(session::ConnectionState::Handshaking);

        HandleClient(clientSock);

        closesocket(clientSock);
        sessionManager_.SetState(session::ConnectionState::Listening);
        if (callbacks_.onStateChanged) callbacks_.onStateChanged(session::ConnectionState::Listening);
    }
}

void LanServer::HandleClient(SOCKET clientSock) {
    // Set TCP_NODELAY and large receive buffer
    int opt = 1;
    setsockopt(clientSock, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&opt), sizeof(opt));
    int bufSize = 1024 * 1024;
    setsockopt(clientSock, SOL_SOCKET, SO_RCVBUF, reinterpret_cast<const char*>(&bufSize), sizeof(bufSize));

    std::vector<uint8_t> rxBuffer;
    rxBuffer.reserve(protocol::kMaxPayloadSize + protocol::kHeaderSize);
    std::vector<uint8_t> readChunk(64 * 1024);

    bool authenticated = false;

    while (isRunning_.load()) {
        int bytesRead = recv(clientSock, reinterpret_cast<char*>(readChunk.data()),
                             static_cast<int>(readChunk.size()), 0);
        if (bytesRead <= 0) break;

        rxBuffer.insert(rxBuffer.end(), readChunk.begin(), readChunk.begin() + bytesRead);

        // Process all complete protocol messages in rxBuffer
        while (rxBuffer.size() >= protocol::kHeaderSize) {
            protocol::Header hdr{};
            if (protocol::DecodeHeader(rxBuffer, hdr) != protocol::DecodeError::None) {
                // Malformed header, close socket
                log::Error("lan", "Malformed protocol header; closing connection");
                return;
            }

            const size_t totalMsgSize = protocol::kHeaderSize + hdr.payloadLength;
            if (rxBuffer.size() < totalMsgSize) {
                // Need more data
                break;
            }

            protocol::Message msg{};
            size_t consumed = 0;
            auto err = protocol::DecodeMessage(rxBuffer, msg, consumed);
            if (err != protocol::DecodeError::None) {
                log::Error("lan", "DecodeMessage failed: " + std::string(protocol::ToString(err)));
                return;
            }

            // Remove processed message bytes
            rxBuffer.erase(rxBuffer.begin(), rxBuffer.begin() + consumed);

            // Handle Message
            if (std::holds_alternative<protocol::Hello>(msg.payload)) {
                auto hello = std::get<protocol::Hello>(msg.payload);
                const auto separator = hello.deviceName.rfind('|');
                const std::string pairingToken = separator == std::string::npos ? "" : hello.deviceName.substr(separator + 1);
                if (separator != std::string::npos) {
                    hello.deviceName.resize(separator);
                }
                log::Info("lan", "Received Hello from device: " + hello.deviceName + " (" + hello.deviceModel + ")");

                // Verify PIN
                auto [ack, isAccepted] = sessionManager_.ProcessHello(hello, pairingToken);
                std::vector<uint8_t> ackBytes;
                protocol::EncodeMessage(ack.assignedSessionId, 1, ack, ackBytes);
                send(clientSock, reinterpret_cast<const char*>(ackBytes.data()), static_cast<int>(ackBytes.size()), 0);

                if (!isAccepted) {
                    log::Error("lan", "Hello authentication rejected: session PIN mismatch");
                    return;
                }
                authenticated = true;
                if (callbacks_.onStateChanged) callbacks_.onStateChanged(session::ConnectionState::Connected);
            } else if (!authenticated) {
                log::Error("lan", "Unauthenticated packet received before Hello; dropping connection");
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
                // Echo heartbeat back to client
                protocol::Heartbeat echoHb = hb;
                echoHb.echoTimestampMicros = hb.timestampMicros;
                echoHb.timestampMicros = static_cast<uint64_t>(
                    std::chrono::duration_cast<std::chrono::microseconds>(
                        std::chrono::steady_clock::now().time_since_epoch()).count());

                std::vector<uint8_t> echoBytes;
                protocol::EncodeMessage(msg.header.sessionId, msg.header.sequence + 1, echoHb, echoBytes);
                send(clientSock, reinterpret_cast<const char*>(echoBytes.data()), static_cast<int>(echoBytes.size()), 0);
            } else if (std::holds_alternative<protocol::Disconnect>(msg.payload)) {
                log::Info("lan", "Client requested disconnect");
                return;
            }
        }
    }
}

}  // namespace castsprint::windows
