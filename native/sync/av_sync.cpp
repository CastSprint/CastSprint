#include "av_sync.hpp"

namespace castsprint::sync {

AvSynchronizer::AvSynchronizer(SyncPreset preset) {
    SetPreset(preset);
}

void AvSynchronizer::SetPreset(SyncPreset preset) noexcept {
    preset_ = preset;
    switch (preset) {
    case SyncPreset::LowLatency:
        maxLateDropThresholdMicros_ = 25'000;   // 25ms: drop aggressively to avoid latency buildup
        onTimeWindowMicros_ = 8'000;
        break;
    case SyncPreset::Balanced:
        maxLateDropThresholdMicros_ = 50'000;   // 50ms: standard balanced window
        onTimeWindowMicros_ = 16'666;
        break;
    case SyncPreset::HighQuality:
        maxLateDropThresholdMicros_ = 120'000;  // 120ms: allow more jitter to avoid dropping
        onTimeWindowMicros_ = 20'000;
        break;
    }
}

void AvSynchronizer::SetUserAudioOffsetMicros(int64_t offsetMicros) noexcept {
    userAudioOffsetMicros_ = offsetMicros;
}

void AvSynchronizer::OnAudioRendered(uint64_t audioPtsMicros, uint64_t hostTimeMicros) noexcept {
    lastAudioPtsMicros_ = audioPtsMicros;
    lastAudioHostTimeMicros_ = hostTimeMicros;
    hasAudioClock_ = true;
}

SyncDecision AvSynchronizer::EvaluateVideoFrame(uint64_t videoPtsMicros, uint64_t hostTimeMicros) noexcept {
    SyncDecision decision;

    if (!hasAudioClock_) {
        // Without an active audio clock, present video frames immediately
        decision.action = VideoAction::PresentNow;
        decision.waitMicros = 0;
        decision.skewMicros = 0;
        return decision;
    }

    // Estimate the current audio presentation timestamp extrapolated by host elapsed time
    const uint64_t elapsedSinceAudio = (hostTimeMicros >= lastAudioHostTimeMicros_)
                                           ? (hostTimeMicros - lastAudioHostTimeMicros_)
                                           : 0;

    // Apply user configurable audio offset (e.g. positive offset means audio is delayed)
    const int64_t currentEffectiveAudioPts = static_cast<int64_t>(lastAudioPtsMicros_ + elapsedSinceAudio) +
                                            userAudioOffsetMicros_;

    // Skew: positive means video frame timestamp is ahead of current audio presentation time
    const int64_t skew = static_cast<int64_t>(videoPtsMicros) - currentEffectiveAudioPts;
    decision.skewMicros = skew;

    // Update smoothed drift estimate using exponential moving average (alpha = 0.1)
    smoothedSkewMicros_ = static_cast<int64_t>(0.9 * static_cast<double>(smoothedSkewMicros_) + 0.1 * static_cast<double>(skew));

    if (skew < -maxLateDropThresholdMicros_) {
        // Video frame is significantly behind current audio playback: drop to catch up
        decision.action = VideoAction::DropLate;
        decision.waitMicros = 0;
    } else if (skew > onTimeWindowMicros_) {
        // Video frame is ahead of audio: wait until scheduled presentation time
        decision.action = VideoAction::Wait;
        decision.waitMicros = std::min(skew, maxWaitThresholdMicros_);
    } else {
        // Frame is within on-time presentation window
        decision.action = VideoAction::PresentNow;
        decision.waitMicros = 0;
    }

    return decision;
}

void AvSynchronizer::Reset() noexcept {
    hasAudioClock_ = false;
    lastAudioPtsMicros_ = 0;
    lastAudioHostTimeMicros_ = 0;
    smoothedSkewMicros_ = 0;
}

}  // namespace castsprint::sync
