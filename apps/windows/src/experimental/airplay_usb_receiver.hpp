#pragma once

#include <string>
#include <vector>
#include <cstdint>
#include <memory>
#include <functional>
#include <map>

namespace castsprint::windows::experimental {

enum class AirPlaySessionState {
    Idle,
    ScanningUsbNetwork,
    WaitingForDevice,
    RtsHandshake,
    StreamingActive,
    Teardown,
    Error
};

struct UsbNetworkInterfaceInfo {
    bool isPresent = false;
    std::wstring adapterName;
    std::wstring friendlyName;
    std::string ipAddress;
    std::string gatewayAddress; // Typically 172.20.10.1 (the iPhone)
    std::string macAddress;
    uint32_t linkSpeedMbps = 0;
};

struct AirPlayStreamMetadata {
    uint32_t width = 1920;
    uint32_t height = 1080;
    double fps = 60.0;
    std::string videoCodec = "H.264";
    std::string audioCodec = "AAC-ELD";
    uint32_t sampleRate = 44100;
    uint32_t channels = 2;
    std::string clientDeviceModel;
    std::string clientOsVersion;
};

struct AirPlayRtspRequest {
    std::string method;
    std::string uri;
    std::string protocolVersion; // e.g. "RTSP/1.0"
    std::map<std::string, std::string> headers;
    std::vector<uint8_t> body;
};

struct AirPlayRtspResponse {
    int statusCode = 200;
    std::string statusText = "OK";
    std::map<std::string, std::string> headers;
    std::vector<uint8_t> body;

    std::string Serialize() const;
};

// Callback for decoded or depacketized media delivery to the CastSprint Direct3D 11 & WASAPI engines
using VideoFrameCallback = std::function<void(const uint8_t* data, size_t size, uint64_t pts)>;
using AudioFrameCallback = std::function<void(const uint8_t* data, size_t size, uint64_t pts)>;

class AirPlayUsbReceiver {
public:
    AirPlayUsbReceiver();
    ~AirPlayUsbReceiver();

    // Scans Windows NDIS adapters for Apple Mobile Device Ethernet
    UsbNetworkInterfaceInfo ProbeAppleUsbNetworkAdapter();

    // Configures the AirPlay receiver endpoints
    bool Initialize(uint16_t rtspPort = 7000);

    // Processes an incoming RTSP message string (from network socket)
    AirPlayRtspResponse HandleRtspMessage(const std::string& rawRtspMessage);

    // Parses raw RTSP text into a structured request
    static bool ParseRtspRequest(const std::string& raw, AirPlayRtspRequest& outRequest);

    // Evaluates whether an incoming SDP payload represents non-DRM screen mirroring
    static bool IsNonDrmScreenMirroring(const std::string& sdpBody);

    // Accessors
    AirPlaySessionState GetState() const { return state_; }
    const UsbNetworkInterfaceInfo& GetActiveInterface() const { return activeInterface_; }
    const AirPlayStreamMetadata& GetStreamMetadata() const { return metadata_; }

    void SetVideoFrameCallback(VideoFrameCallback cb) { videoCallback_ = std::move(cb); }
    void SetAudioFrameCallback(AudioFrameCallback cb) { audioCallback_ = std::move(cb); }

    // Mock/Simulated injection for automated testing on non-Windows host
    void InjectMockUsbNetwork(const UsbNetworkInterfaceInfo& mockInterface);

private:
    AirPlayRtspResponse HandleOptions(const AirPlayRtspRequest& req);
    AirPlayRtspResponse HandleAnnounce(const AirPlayRtspRequest& req);
    AirPlayRtspResponse HandleSetup(const AirPlayRtspRequest& req);
    AirPlayRtspResponse HandleRecord(const AirPlayRtspRequest& req);
    AirPlayRtspResponse HandleTeardown(const AirPlayRtspRequest& req);

    AirPlaySessionState state_ = AirPlaySessionState::Idle;
    UsbNetworkInterfaceInfo activeInterface_;
    AirPlayStreamMetadata metadata_;
    uint16_t rtspPort_ = 7000;
    uint32_t sessionCSeq_ = 0;
    std::string sessionId_ = "1";

    VideoFrameCallback videoCallback_;
    AudioFrameCallback audioCallback_;
};

} // namespace castsprint::windows::experimental
