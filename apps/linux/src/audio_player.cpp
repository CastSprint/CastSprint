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
    isConfigured_ = false;

    Log(LogLevel::Error, "Linux audio output backend is not implemented; audio frames will not be reported as played");
    return false;
}

bool AudioPlayer::PlayFrame(const protocol::AudioFrame& frame) {
    if (!isConfigured_ || frame.data.empty() || isMuted_.load()) {
        return false;
    }
    Log(LogLevel::Error, "Dropping audio frame because no Linux audio output backend is available");
    return false;
}

void AudioPlayer::Stop() {
    isConfigured_ = false;
}

} // namespace castsprint::linux_app
