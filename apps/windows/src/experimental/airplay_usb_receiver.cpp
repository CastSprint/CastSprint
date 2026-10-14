#include "airplay_usb_receiver.hpp"

#include <sstream>
#include <iostream>
#include <algorithm>
#include <cstring>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")
#endif

namespace castsprint::windows::experimental {

AirPlayUsbReceiver::AirPlayUsbReceiver() {
    metadata_.width = 1920;
    metadata_.height = 1080;
    metadata_.fps = 60.0;
    metadata_.videoCodec = "H.264";
    metadata_.audioCodec = "AAC-ELD";
}

AirPlayUsbReceiver::~AirPlayUsbReceiver() {
    state_ = AirPlaySessionState::Idle;
}

UsbNetworkInterfaceInfo AirPlayUsbReceiver::ProbeAppleUsbNetworkAdapter() {
#ifdef _WIN32
    UsbNetworkInterfaceInfo info;
    ULONG bufferSize = 15000;
    std::vector<BYTE> buffer(bufferSize);
    PIP_ADAPTER_ADDRESSES addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());

    ULONG ret = GetAdaptersAddresses(AF_INET, GAA_FLAG_INCLUDE_GATEWAYS, nullptr, addresses, &bufferSize);
    if (ret == ERROR_BUFFER_OVERFLOW) {
        buffer.resize(bufferSize);
        addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
        ret = GetAdaptersAddresses(AF_INET, GAA_FLAG_INCLUDE_GATEWAYS, nullptr, addresses, &bufferSize);
    }

    if (ret == NO_ERROR) {
        for (PIP_ADAPTER_ADDRESSES cur = addresses; cur != nullptr; cur = cur->Next) {
            std::wstring desc = cur->Description ? cur->Description : L"";
            std::wstring friendly = cur->FriendlyName ? cur->FriendlyName : L"";

            std::wstring descUpper = desc;
            std::transform(descUpper.begin(), descUpper.end(), descUpper.begin(), ::towupper);

            // Apple Mobile Device Ethernet NDIS adapter
            bool isAppleAdapter = (descUpper.find(L"APPLE MOBILE DEVICE ETHERNET") != std::wstring::npos) ||
                                  (descUpper.find(L"APPLE") != std::wstring::npos && descUpper.find(L"ETHERNET") != std::wstring::npos);

            // Also check for standard iOS USB tethering subnet: 172.20.10.x
            std::string ipStr;
            for (PIP_ADAPTER_UNICAST_ADDRESS uAddr = cur->FirstUnicastAddress; uAddr != nullptr; uAddr = uAddr->Next) {
                if (uAddr->Address.lpSockaddr->sa_family == AF_INET) {
                    sockaddr_in* sa = reinterpret_cast<sockaddr_in*>(uAddr->Address.lpSockaddr);
                    char ipBuffer[INET_ADDRSTRLEN] = {0};
                    inet_ntop(AF_INET, &(sa->sin_addr), ipBuffer, INET_ADDRSTRLEN);
                    ipStr = ipBuffer;
                    if (ipStr.find("172.20.10.") == 0) {
                        isAppleAdapter = true;
                    }
                    break;
                }
            }

            if (isAppleAdapter) {
                info.isPresent = true;
                info.adapterName = cur->AdapterName ? std::wstring(cur->AdapterName, cur->AdapterName + strlen(cur->AdapterName)) : L"";
                info.friendlyName = friendly.empty() ? desc : friendly;
                info.ipAddress = ipStr;

                if (cur->FirstGatewayAddress && cur->FirstGatewayAddress->Address.lpSockaddr->sa_family == AF_INET) {
                    sockaddr_in* gw = reinterpret_cast<sockaddr_in*>(cur->FirstGatewayAddress->Address.lpSockaddr);
                    char gwBuffer[INET_ADDRSTRLEN] = {0};
                    inet_ntop(AF_INET, &(gw->sin_addr), gwBuffer, INET_ADDRSTRLEN);
                    info.gatewayAddress = gwBuffer;
                } else if (!ipStr.empty()) {
                    info.gatewayAddress = "172.20.10.1"; // Standard iOS Hotspot default gateway
                }

                info.linkSpeedMbps = static_cast<uint32_t>(cur->TransmitLinkSpeed / 1000000);
                activeInterface_ = info;
                state_ = AirPlaySessionState::WaitingForDevice;
                return info;
            }
        }
    }
#endif

    return activeInterface_;
}

void AirPlayUsbReceiver::InjectMockUsbNetwork(const UsbNetworkInterfaceInfo& mockInterface) {
    activeInterface_ = mockInterface;
    if (mockInterface.isPresent) {
        state_ = AirPlaySessionState::WaitingForDevice;
    }
}

bool AirPlayUsbReceiver::Initialize(uint16_t rtspPort) {
    rtspPort_ = rtspPort;
    if (activeInterface_.isPresent) {
        state_ = AirPlaySessionState::WaitingForDevice;
    } else {
        state_ = AirPlaySessionState::ScanningUsbNetwork;
    }
    return true;
}

bool AirPlayUsbReceiver::ParseRtspRequest(const std::string& raw, AirPlayRtspRequest& outRequest) {
    outRequest.headers.clear();
    outRequest.body.clear();

    std::istringstream stream(raw);
    std::string requestLine;
    if (!std::getline(stream, requestLine) || requestLine.empty()) {
        return false;
    }

    // Strip trailing \r if present
    if (!requestLine.empty() && requestLine.back() == '\r') {
        requestLine.pop_back();
    }

    std::istringstream reqStream(requestLine);
    reqStream >> outRequest.method >> outRequest.uri >> outRequest.protocolVersion;
    if (outRequest.method.empty() || outRequest.protocolVersion.empty()) {
        return false;
    }

    std::string headerLine;
    while (std::getline(stream, headerLine) && !headerLine.empty()) {
        if (!headerLine.empty() && headerLine.back() == '\r') {
            headerLine.pop_back();
        }
        if (headerLine.empty()) {
            break; // Header/body delimiter
        }

        auto colonPos = headerLine.find(':');
        if (colonPos != std::string::npos) {
            std::string key = headerLine.substr(0, colonPos);
            std::string val = headerLine.substr(colonPos + 1);
            // Trim leading whitespace on value
            val.erase(0, val.find_first_not_of(" \t"));
            outRequest.headers[key] = val;
        }
    }

    // Read remaining body if Content-Length specified
    auto it = outRequest.headers.find("Content-Length");
    if (it != outRequest.headers.end()) {
        size_t contentLength = static_cast<size_t>(std::stoul(it->second));
        std::vector<char> bodyBuf(contentLength);
        stream.read(bodyBuf.data(), static_cast<std::streamsize>(contentLength));
        outRequest.body.assign(bodyBuf.begin(), bodyBuf.end());
    }

    return true;
}

std::string AirPlayRtspResponse::Serialize() const {
    std::ostringstream ss;
    ss << "RTSP/1.0 " << statusCode << " " << statusText << "\r\n";
    for (const auto& [k, v] : headers) {
        ss << k << ": " << v << "\r\n";
    }
    if (!body.empty()) {
        ss << "Content-Length: " << body.size() << "\r\n";
    }
    ss << "\r\n";
    if (!body.empty()) {
        ss.write(reinterpret_cast<const char*>(body.data()), static_cast<std::streamsize>(body.size()));
    }
    return ss.str();
}

bool AirPlayUsbReceiver::IsNonDrmScreenMirroring(const std::string& sdpBody) {
    // AirPlay Screen Mirroring (desktop, gaming, photos) produces standard H.264 streams
    // without requiring FairPlay DRM key blocks.
    if (sdpBody.find("m=video") != std::string::npos && sdpBody.find("H264") != std::string::npos) {
        // True if not encumbered by FairPlay content DRM
        if (sdpBody.find("fairplay") == std::string::npos && sdpBody.find("kFairPlayKey") == std::string::npos) {
            return true;
        }
    }
    // Also true if standard video display mirror
    return sdpBody.find("screen-mirror") != std::string::npos || sdpBody.find("CastSprint") != std::string::npos;
}

AirPlayRtspResponse AirPlayUsbReceiver::HandleRtspMessage(const std::string& rawRtspMessage) {
    AirPlayRtspRequest req;
    if (!ParseRtspRequest(rawRtspMessage, req)) {
        AirPlayRtspResponse badReq;
        badReq.statusCode = 400;
        badReq.statusText = "Bad Request";
        return badReq;
    }

    if (req.method == "OPTIONS") {
        return HandleOptions(req);
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
    AirPlayRtspResponse resp;
    resp.statusCode = 200;
    resp.statusText = "OK";
    auto cseqIt = req.headers.find("CSeq");
    if (cseqIt != req.headers.end()) {
        resp.headers["CSeq"] = cseqIt->second;
    }
    resp.headers["Server"] = "AirTunes/220.68";
    return resp;
}

AirPlayRtspResponse AirPlayUsbReceiver::HandleOptions(const AirPlayRtspRequest& req) {
    AirPlayRtspResponse resp;
    resp.statusCode = 200;
    resp.statusText = "OK";

    auto cseqIt = req.headers.find("CSeq");
    if (cseqIt != req.headers.end()) {
        resp.headers["CSeq"] = cseqIt->second;
    }

    resp.headers["Server"] = "AirTunes/220.68";
    resp.headers["Public"] = "ANNOUNCE, SETUP, RECORD, PAUSE, TEARDOWN, OPTIONS, GET_PARAMETER, SET_PARAMETER";
    state_ = AirPlaySessionState::RtsHandshake;
    return resp;
}

AirPlayRtspResponse AirPlayUsbReceiver::HandleAnnounce(const AirPlayRtspRequest& req) {
    AirPlayRtspResponse resp;
    resp.statusCode = 200;
    resp.statusText = "OK";

    auto cseqIt = req.headers.find("CSeq");
    if (cseqIt != req.headers.end()) {
        resp.headers["CSeq"] = cseqIt->second;
    }

    resp.headers["Server"] = "AirTunes/220.68";

    std::string sdp(reinterpret_cast<const char*>(req.body.data()), req.body.size());
    if (IsNonDrmScreenMirroring(sdp)) {
        metadata_.videoCodec = "H.264";
        metadata_.width = 1920;
        metadata_.height = 1080;
    }

    return resp;
}

AirPlayRtspResponse AirPlayUsbReceiver::HandleSetup(const AirPlayRtspRequest& req) {
    AirPlayRtspResponse resp;
    resp.statusCode = 200;
    resp.statusText = "OK";

    auto cseqIt = req.headers.find("CSeq");
    if (cseqIt != req.headers.end()) {
        resp.headers["CSeq"] = cseqIt->second;
    }

    resp.headers["Server"] = "AirTunes/220.68";
    resp.headers["Session"] = sessionId_;

    // Negotiate transport ports for RTP video and audio
    auto transIt = req.headers.find("Transport");
    if (transIt != req.headers.end()) {
        resp.headers["Transport"] = transIt->second + ";server_port=7010;control_port=7011";
    } else {
        resp.headers["Transport"] = "RTP/AVP/UDP;unicast;server_port=7010;control_port=7011";
    }

    return resp;
}

AirPlayRtspResponse AirPlayUsbReceiver::HandleRecord(const AirPlayRtspRequest& req) {
    AirPlayRtspResponse resp;
    resp.statusCode = 200;
    resp.statusText = "OK";

    auto cseqIt = req.headers.find("CSeq");
    if (cseqIt != req.headers.end()) {
        resp.headers["CSeq"] = cseqIt->second;
    }

    resp.headers["Server"] = "AirTunes/220.68";
    resp.headers["Session"] = sessionId_;
    state_ = AirPlaySessionState::StreamingActive;
    return resp;
}

AirPlayRtspResponse AirPlayUsbReceiver::HandleTeardown(const AirPlayRtspRequest& req) {
    AirPlayRtspResponse resp;
    resp.statusCode = 200;
    resp.statusText = "OK";

    auto cseqIt = req.headers.find("CSeq");
    if (cseqIt != req.headers.end()) {
        resp.headers["CSeq"] = cseqIt->second;
    }

    resp.headers["Server"] = "AirTunes/220.68";
    state_ = AirPlaySessionState::Teardown;
    return resp;
}

} // namespace castsprint::windows::experimental
