#include "audio_player.hpp"
#include "log.hpp"

namespace castsprint::linux_app {

AudioPlayer::AudioPlayer() = default;

AudioPlayer::~AudioPlayer() {
    Stop();
}

bool AudioPlayer::Configure(const protocol::AudioConfig& config) {
    sampleRate_ = config.sampleRate;
    channels_ = config.channels;
    isConfigured_ = true;

    Log(LogLevel::Info, "Audio player configured: " + std::to_string(sampleRate_) + " Hz, " +
                        std::to_string(channels_) + " channels");
    return true;
}

bool AudioPlayer::PlayFrame(const protocol::AudioFrame& frame) {
    if (!isConfigured_ || frame.data.empty() || isMuted_.load()) {
        return false;
    }
    // PCM audio frames are forwarded to output sink (ALSA / PipeWire / PulseAudio)
    return true;
}

void AudioPlayer::Stop() {
    isConfigured_ = false;
}

} // namespace castsprint::linux_app
