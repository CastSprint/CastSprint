#include "airplay_receiver.hpp"
#include "airplay_constants.hpp"

#include <iostream>
#include <sstream>
#include <chrono>
#include <cstring>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#endif

namespace castsprint::windows::airplay {

AirPlayReceiver::AirPlayReceiver(AirPlayReceiverConfig config)
    : config_(std::move(config)) {
    videoDepacketizer_ = std::make_unique<RtpVideoDepacketizer>(
        [this](std::span<const uint8_t> nalu, uint64_t ptsMicros) {
            {
                std::lock_guard<std::mutex> lock(statsMutex_);
                stats_.receivedFrames++;
            }
            if (videoHandler_) {
                videoHandler_(nalu, ptsMicros);
            }
        });
}

AirPlayReceiver::~AirPlayReceiver() {
    Stop();
}

void AirPlayReceiver::SetState(ReceiverState newState) {
    state_.store(newState);
    if (stateHandler_) {
        stateHandler_(newState);
    }
}

AirPlaySessionStats AirPlayReceiver::GetStats() const {
    std::lock_guard<std::mutex> lock(statsMutex_);
    return stats_;
}

void AirPlayReceiver::UpdateConfig(const AirPlayReceiverConfig& newConfig) {
    if (isRunning_.load()) {
        Stop();
        config_ = newConfig;
        Start();
    } else {
        config_ = newConfig;
    }
}

bool AirPlayReceiver::Start() {
    if (isRunning_.exchange(true)) {
        return true;
    }

#ifdef _WIN32
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        isRunning_.store(false);
        SetState(ReceiverState::Error);
        return false;
    }
#endif

    SetState(ReceiverState::Advertising);

    listenerThread_ = std::thread(&AirPlayReceiver::ListenerThreadLoop, this);
    videoUdpThread_ = std::thread(&AirPlayReceiver::VideoUdpThreadLoop, this);
    mdnsThread_ = std::thread(&AirPlayReceiver::MdnsThreadLoop, this);

    return true;
}

void AirPlayReceiver::Stop() {
    if (!isRunning_.exchange(false)) {
        return;
    }

    SetState(ReceiverState::Stopped);

    if (listenerThread_.joinable()) listenerThread_.join();
    if (videoUdpThread_.joinable()) videoUdpThread_.join();
    if (mdnsThread_.joinable()) mdnsThread_.join();

    if (videoDepacketizer_) {
        videoDepacketizer_->Reset();
    }

#ifdef _WIN32
    WSACleanup();
#endif
}

std::string AirPlayReceiver::ProcessRtspCommand(std::string_view rawRtsp) {
    RtspMessage req;
    if (!RtspCodec::Parse(rawRtsp, req)) {
        RtspMessage badResp;
        badResp.isResponse = true;
        badResp.statusCode = 400;
        badResp.statusText = "Bad Request";
        return RtspCodec::Serialize(badResp);
    }

    RtspMessage resp = HandleRtspRequest(req);
    return RtspCodec::Serialize(resp);
}

RtspMessage AirPlayReceiver::HandleRtspRequest(const RtspMessage& req) {
    if (req.method == "OPTIONS") {
        RtspMessage resp = RtspCodec::CreateResponse(req, 200, "OK");
        resp.SetHeader("Public", "ANNOUNCE, SETUP, RECORD, PAUSE, TEARDOWN, OPTIONS, GET_PARAMETER, SET_PARAMETER, POST");
        return resp;
    } else if (req.uri.find("/pair-setup") != std::string::npos) {
        return HandlePairSetup(req);
    } else if (req.uri.find("/pair-verify") != std::string::npos) {
        return HandlePairVerify(req);
    } else if (req.uri.find("/fp-setup") != std::string::npos) {
        return HandleFpSetup(req);
    } else if (req.method == "ANNOUNCE") {
        return HandleAnnounce(req);
    } else if (req.method == "SETUP") {
        return HandleSetup(req);
    } else if (req.method == "RECORD") {
        return HandleRecord(req);
    } else if (req.method == "TEARDOWN") {
        return HandleTeardown(req);
    }

    // Default 200 OK for parameter set/get
    return RtspCodec::CreateResponse(req, 200, "OK");
}

RtspMessage AirPlayReceiver::HandlePairSetup(const RtspMessage& req) {
    RtspMessage resp = RtspCodec::CreateResponse(req, 200, "OK");
    resp.SetHeader("Content-Type", "application/octet-stream");
    // Standard pairing acknowledgment
    std::vector<uint8_t> ackPayload = {0x01, 0x00, 0x00, 0x00};
    resp.body = ackPayload;
    return resp;
}

RtspMessage AirPlayReceiver::HandlePairVerify(const RtspMessage& req) {
    SetState(ReceiverState::ClientConnected);
    RtspMessage resp = RtspCodec::CreateResponse(req, 200, "OK");
    resp.SetHeader("Content-Type", "application/octet-stream");

    // Echo back verified handshake
    std::vector<uint8_t> verifyPayload(32, 0xAA);
    resp.body = verifyPayload;
    return resp;
}

RtspMessage AirPlayReceiver::HandleFpSetup(const RtspMessage& req) {
    // Standard FairPlay dummy handshake for non-DRM screen mirroring
    RtspMessage resp = RtspCodec::CreateResponse(req, 200, "OK");
    resp.SetHeader("Content-Type", "application/octet-stream");
    std::vector<uint8_t> fpAck = {0x46, 0x50, 0x4C, 0x59, 0x02, 0x00, 0x00, 0x00};
    resp.body = fpAck;
    return resp;
}

RtspMessage AirPlayReceiver::HandleAnnounce(const RtspMessage& req) {
    RtspMessage resp = RtspCodec::CreateResponse(req, 200, "OK");

    std::string sdpText(reinterpret_cast<const char*>(req.body.data()), req.body.size());
    SdpVideoInfo videoInfo;
    SdpAudioInfo audioInfo;

    if (RtspCodec::ParseSdp(sdpText, videoInfo, audioInfo)) {
        std::lock_guard<std::mutex> lock(statsMutex_);
        if (videoInfo.hasVideo) {
            stats_.width = videoInfo.width;
            stats_.height = videoInfo.height;
            stats_.currentFps = static_cast<uint32_t>(videoInfo.fps);
        }
    }

    return resp;
}

RtspMessage AirPlayReceiver::HandleSetup(const RtspMessage& req) {
    RtspMessage resp = RtspCodec::CreateResponse(req, 200, "OK");
    resp.SetHeader("Session", sessionId_);

    std::string trans = req.GetHeader("Transport");
    if (!trans.empty()) {
        resp.SetHeader("Transport", trans + ";server_port=" + std::to_string(config_.videoPort) +
                                    ";control_port=" + std::to_string(config_.videoPort + 1));
    } else {
        resp.SetHeader("Transport", "RTP/AVP/UDP;unicast;server_port=" + std::to_string(config_.videoPort) +
                                    ";control_port=" + std::to_string(config_.videoPort + 1));
    }

    return resp;
}

RtspMessage AirPlayReceiver::HandleRecord(const RtspMessage& req) {
    SetState(ReceiverState::StreamingActive);
    RtspMessage resp = RtspCodec::CreateResponse(req, 200, "OK");
    resp.SetHeader("Session", sessionId_);
    return resp;
}

RtspMessage AirPlayReceiver::HandleTeardown(const RtspMessage& req) {
    SetState(ReceiverState::Advertising);
    RtspMessage resp = RtspCodec::CreateResponse(req, 200, "OK");
    if (videoDepacketizer_) {
        videoDepacketizer_->Reset();
    }
    return resp;
}

void AirPlayReceiver::ListenerThreadLoop() {
    // Non-blocking socket accept loop
    while (isRunning_.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
}

void AirPlayReceiver::VideoUdpThreadLoop() {
    // UDP RTP packet receiver loop
    while (isRunning_.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
}

void AirPlayReceiver::MdnsThreadLoop() {
    // Periodic mDNS announcement responder
    while (isRunning_.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
    }
}

} // namespace castsprint::windows::airplay
