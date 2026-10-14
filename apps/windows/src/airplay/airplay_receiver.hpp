#pragma once

#include "airplay_constants.hpp"
#include "airplay_rtsp_codec.hpp"

#include <string>
#include <vector>
#include <atomic>
#include <thread>
#include <mutex>
#include <functional>
#include <span>

namespace castsprint::windows::airplay {

enum class ReceiverState {
    Stopped,
    Advertising,
    ClientConnected,
    StreamingActive,
    Error
};

struct AirPlayReceiverConfig {
    std::string receiverName = std::string(kDefaultReceiverName);
    uint16_t rtspPort = kDefaultRtspPort;
    uint16_t videoPort = kDefaultVideoRtpPort;
    uint16_t audioPort = kDefaultAudioRtpPort;
    bool enableUsbHotspotOnly = false;
    std::string bindIp = "0.0.0.0";
};

struct AirPlaySessionStats {
    uint32_t receivedFrames = 0;
    uint32_t droppedFrames = 0;
    uint32_t currentFps = 0;
    uint32_t currentBitrateBps = 0;
    uint32_t width = 1920;
    uint32_t height = 1080;
    std::string clientModel;
    std::string clientIp;
};

using VideoFrameHandler = std::function<void(std::span<const uint8_t> nalu, uint64_t ptsMicros)>;
using AudioFrameHandler = std::function<void(std::span<const uint8_t> audioData, uint64_t ptsMicros)>;
using StateChangedHandler = std::function<void(ReceiverState newState)>;

class AirPlayReceiver {
public:
    explicit AirPlayReceiver(AirPlayReceiverConfig config = {});
    ~AirPlayReceiver();

    AirPlayReceiver(const AirPlayReceiver&) = delete;
    AirPlayReceiver& operator=(const AirPlayReceiver&) = delete;

    // Starts network listener and mDNS advertising
    bool Start();
    void Stop();

    bool IsRunning() const noexcept { return isRunning_.load(); }
    ReceiverState State() const noexcept { return state_.load(); }

    void SetVideoHandler(VideoFrameHandler handler) { videoHandler_ = std::move(handler); }
    void SetAudioHandler(AudioFrameHandler handler) { audioHandler_ = std::move(handler); }
    void SetStateChangedHandler(StateChangedHandler handler) { stateHandler_ = std::move(handler); }

    AirPlaySessionStats GetStats() const;
    const AirPlayReceiverConfig& GetConfig() const noexcept { return config_; }
    void UpdateConfig(const AirPlayReceiverConfig& newConfig);

    // Diagnostic/Testing: Ingests an RTSP string directly (used by unit tests)
    std::string ProcessRtspCommand(std::string_view rawRtsp);

private:
    void ListenerThreadLoop();
    void VideoUdpThreadLoop();
    void MdnsThreadLoop();

    RtspMessage HandleRtspRequest(const RtspMessage& req);
    RtspMessage HandlePairSetup(const RtspMessage& req);
    RtspMessage HandlePairVerify(const RtspMessage& req);
    RtspMessage HandleFpSetup(const RtspMessage& req);
    RtspMessage HandleAnnounce(const RtspMessage& req);
    RtspMessage HandleSetup(const RtspMessage& req);
    RtspMessage HandleRecord(const RtspMessage& req);
    RtspMessage HandleTeardown(const RtspMessage& req);

    void SetState(ReceiverState newState);

    AirPlayReceiverConfig config_;
    std::atomic<bool> isRunning_{false};
    std::atomic<ReceiverState> state_{ReceiverState::Stopped};

    VideoFrameHandler videoHandler_;
    AudioFrameHandler audioHandler_;
    StateChangedHandler stateHandler_;

    std::unique_ptr<RtpVideoDepacketizer> videoDepacketizer_;

    std::thread listenerThread_;
    std::thread videoUdpThread_;
    std::thread mdnsThread_;

    mutable std::mutex statsMutex_;
    AirPlaySessionStats stats_;

    std::string sessionId_ = "1";
    uint64_t sessionStartTime_ = 0;
};

} // namespace castsprint::windows::airplay
