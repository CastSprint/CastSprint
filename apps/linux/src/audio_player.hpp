#pragma once
#include <cstdint>
#include <vector>
#include <span>
#include <atomic>
#include "castsprint/protocol/protocol.hpp"

namespace castsprint::linux_app {

class AudioPlayer {
public:
    AudioPlayer();
    ~AudioPlayer();

    bool Configure(const protocol::AudioConfig& config);
    bool PlayFrame(const protocol::AudioFrame& frame);
    void Stop();

    void SetVolume(float volume) noexcept { volume_.store(volume); }
    void SetMuted(bool muted) noexcept { isMuted_.store(muted); }

private:
    uint32_t sampleRate_{48000};
    uint8_t channels_{2};
    std::atomic<float> volume_{1.0f};
    std::atomic<bool> isMuted_{false};
    bool isConfigured_{false};
};

} // namespace castsprint::linux_app
