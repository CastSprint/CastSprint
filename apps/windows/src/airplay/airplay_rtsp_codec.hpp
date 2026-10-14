#pragma once

#include <string>
#include <vector>
#include <map>
#include <cstdint>
#include <span>
#include <functional>

namespace castsprint::windows::airplay {

struct RtspMessage {
    std::string method;         // e.g. "OPTIONS", "ANNOUNCE", "SETUP", "RECORD", "POST"
    std::string uri;            // e.g. "rtsp://172.20.10.2/stream", "/pair-setup"
    std::string protocol;       // e.g. "RTSP/1.0"
    std::map<std::string, std::string> headers;
    std::vector<uint8_t> body;

    int statusCode = 200;
    std::string statusText = "OK";
    bool isResponse = false;

    std::string GetHeader(const std::string& key) const;
    void SetHeader(const std::string& key, const std::string& value);
};

struct SdpVideoInfo {
    bool hasVideo = false;
    std::string codec = "H264";
    uint32_t width = 1920;
    uint32_t height = 1080;
    double fps = 60.0;
    uint8_t payloadType = 96;
    std::vector<uint8_t> sps;
    std::vector<uint8_t> pps;
    bool isNonDrmMirror = true;
};

struct SdpAudioInfo {
    bool hasAudio = false;
    std::string codec = "AAC-ELD";
    uint32_t sampleRate = 44100;
    uint8_t channels = 2;
    uint8_t payloadType = 96;
};

class RtspCodec {
public:
    // Parses raw text buffer into RtspMessage
    static bool Parse(std::string_view raw, RtspMessage& outMsg);

    // Serializes RtspMessage to string for transmission
    static std::string Serialize(const RtspMessage& msg);

    // Parses SDP session description body
    static bool ParseSdp(std::string_view sdpText, SdpVideoInfo& outVideo, SdpAudioInfo& outAudio);

    // Helper: Formulates a standard 200 OK RTSP response matching a request
    static RtspMessage CreateResponse(const RtspMessage& req, int statusCode = 200, std::string_view statusText = "OK");
};

// Reassembles raw H.264 NALUs from RTP packets (including FU-A fragmentation units)
class RtpVideoDepacketizer {
public:
    using FrameReadyCallback = std::function<void(std::span<const uint8_t> nalu, uint64_t pts)>;

    explicit RtpVideoDepacketizer(FrameReadyCallback onFrame);
    ~RtpVideoDepacketizer() = default;

    // Ingests raw RTP packet (including 12-byte header)
    bool ProcessRtpPacket(std::span<const uint8_t> packet);

    void Reset();

private:
    FrameReadyCallback onFrame_;
    std::vector<uint8_t> fuAssemblyBuffer_;
    uint32_t lastTimestamp_ = 0;
    bool inFuA_ = false;
};

} // namespace castsprint::windows::airplay
