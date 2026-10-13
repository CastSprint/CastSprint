// CastSprint Audio/Video Synchronizer
// Normative specification: docs/architecture/AUDIO_AND_LAN.md
#pragma once

#include <cstdint>
#include <chrono>
#include <algorithm>
#include <cmath>

namespace castsprint::sync {

enum class VideoAction {
    PresentNow,
    Wait,
    DropLate
};

struct SyncDecision {
    VideoAction action = VideoAction::PresentNow;
    int64_t waitMicros = 0;
    int64_t skewMicros = 0;  // positive means video is ahead of audio
};

enum class SyncPreset {
    LowLatency,   // Tight buffer (~10ms), aggressive late-frame dropping
    Balanced,     // Moderate buffer (~35ms), smooth presentation
    HighQuality   // Stable buffer (~70ms), prioritizing zero dropped frames
};

class AvSynchronizer {
public:
    explicit AvSynchronizer(SyncPreset preset = SyncPreset::Balanced);

    void SetPreset(SyncPreset preset) noexcept;
    void SetUserAudioOffsetMicros(int64_t offsetMicros) noexcept;
    int64_t UserAudioOffsetMicros() const noexcept { return userAudioOffsetMicros_; }

    // Notifies the synchronizer of the current audio position rendered by WASAPI
    void OnAudioRendered(uint64_t audioPtsMicros, uint64_t hostTimeMicros) noexcept;

    // Evaluates a video frame's presentation schedule against the audio clock
    SyncDecision EvaluateVideoFrame(uint64_t videoPtsMicros, uint64_t hostTimeMicros) noexcept;

    // Returns estimated current audio-video drift in microseconds
    int64_t EstimatedDriftMicros() const noexcept { return smoothedSkewMicros_; }

    // Resets synchronizer state on stream restart or seek
    void Reset() noexcept;

private:
    SyncPreset preset_ = SyncPreset::Balanced;
    int64_t userAudioOffsetMicros_ = 0;

    bool hasAudioClock_ = false;
    uint64_t lastAudioPtsMicros_ = 0;
    uint64_t lastAudioHostTimeMicros_ = 0;

    int64_t smoothedSkewMicros_ = 0;
    int64_t maxLateDropThresholdMicros_ = 50'000;   // 50ms default
    int64_t maxWaitThresholdMicros_ = 200'000;      // 200ms clamp for crazy timestamps
    int64_t onTimeWindowMicros_ = 16'666;           // ~1 frame at 60fps
};

}  // namespace castsprint::sync
