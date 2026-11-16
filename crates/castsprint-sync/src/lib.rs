//! CastSprint Audio/Video Synchronizer and Drift Estimator.
//! Normative specification: `docs/architecture/AUDIO_AND_LAN.md`

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum VideoAction {
    PresentNow = 0,
    Wait = 1,
    DropLate = 2,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SyncDecision {
    pub action: VideoAction,
    pub wait_micros: i64,
    pub skew_micros: i64, // positive means video is ahead of audio
}

impl Default for SyncDecision {
    fn default() -> Self {
        Self {
            action: VideoAction::PresentNow,
            wait_micros: 0,
            skew_micros: 0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum SyncPreset {
    LowLatency = 0, // Tight buffer (~10ms), aggressive late-frame dropping
    #[default]
    Balanced = 1,   // Moderate buffer (~35ms), smooth presentation
    HighQuality = 2, // Stable buffer (~70ms), prioritizing zero dropped frames
}

pub struct AvSynchronizer {
    preset: SyncPreset,
    user_audio_offset_micros: i64,
    has_audio_clock: bool,
    last_audio_pts_micros: u64,
    last_audio_host_time_micros: u64,
    smoothed_skew_micros: i64,
    max_late_drop_threshold_micros: i64,
    max_wait_threshold_micros: i64,
    on_time_window_micros: i64,
}

impl Default for AvSynchronizer {
    fn default() -> Self {
        Self::new(SyncPreset::Balanced)
    }
}

impl AvSynchronizer {
    pub fn new(preset: SyncPreset) -> Self {
        let mut sync = Self {
            preset: SyncPreset::Balanced,
            user_audio_offset_micros: 0,
            has_audio_clock: false,
            last_audio_pts_micros: 0,
            last_audio_host_time_micros: 0,
            smoothed_skew_micros: 0,
            max_late_drop_threshold_micros: 50_000,
            max_wait_threshold_micros: 200_000,
            on_time_window_micros: 16_666,
        };
        sync.set_preset(preset);
        sync
    }

    pub fn set_preset(&mut self, preset: SyncPreset) {
        self.preset = preset;
        match preset {
            SyncPreset::LowLatency => {
                self.max_late_drop_threshold_micros = 25_000; // 25ms: drop aggressively
                self.on_time_window_micros = 8_000;
            }
            SyncPreset::Balanced => {
                self.max_late_drop_threshold_micros = 50_000; // 50ms: standard balanced window
                self.on_time_window_micros = 16_666;
            }
            SyncPreset::HighQuality => {
                self.max_late_drop_threshold_micros = 120_000; // 120ms: allow more jitter
                self.on_time_window_micros = 20_000;
            }
        }
    }

    pub fn preset(&self) -> SyncPreset {
        self.preset
    }

    pub fn set_user_audio_offset_micros(&mut self, offset_micros: i64) {
        self.user_audio_offset_micros = offset_micros;
    }

    pub fn user_audio_offset_micros(&self) -> i64 {
        self.user_audio_offset_micros
    }

    /// Notifies the synchronizer of the current audio position rendered by hardware (WASAPI / CoreAudio / PipeWire).
    pub fn on_audio_rendered(&mut self, audio_pts_micros: u64, host_time_micros: u64) {
        self.last_audio_pts_micros = audio_pts_micros;
        self.last_audio_host_time_micros = host_time_micros;
        self.has_audio_clock = true;
    }

    /// Evaluates a video frame's presentation schedule against the audio clock.
    pub fn evaluate_video_frame(
        &mut self,
        video_pts_micros: u64,
        host_time_micros: u64,
    ) -> SyncDecision {
        if !self.has_audio_clock {
            // Without an active audio clock, present video frames immediately
            return SyncDecision {
                action: VideoAction::PresentNow,
                wait_micros: 0,
                skew_micros: 0,
            };
        }

        // Estimate current audio presentation timestamp extrapolated by host elapsed time
        let elapsed_since_audio = if host_time_micros >= self.last_audio_host_time_micros {
            host_time_micros - self.last_audio_host_time_micros
        } else {
            0
        };

        // Apply user configurable audio offset (e.g. positive offset means audio is delayed)
        let current_effective_audio_pts =
            (self.last_audio_pts_micros + elapsed_since_audio) as i64 + self.user_audio_offset_micros;

        // Skew: positive means video frame timestamp is ahead of current audio presentation time
        let skew = video_pts_micros as i64 - current_effective_audio_pts;

        // Update smoothed drift estimate using exponential moving average (alpha = 0.1)
        self.smoothed_skew_micros =
            (0.9 * self.smoothed_skew_micros as f64 + 0.1 * skew as f64) as i64;

        let action = if skew < -self.max_late_drop_threshold_micros {
            // Video frame is significantly behind current audio playback: drop to catch up
            VideoAction::DropLate
        } else if skew > self.on_time_window_micros {
            // Video frame is ahead of audio: wait until scheduled presentation time
            VideoAction::Wait
        } else {
            // Frame is within on-time presentation window
            VideoAction::PresentNow
        };

        let wait_micros = if action == VideoAction::Wait {
            skew.min(self.max_wait_threshold_micros)
        } else {
            0
        };

        SyncDecision {
            action,
            wait_micros,
            skew_micros: skew,
        }
    }

    /// Returns estimated current audio-video drift in microseconds.
    pub fn estimated_drift_micros(&self) -> i64 {
        self.smoothed_skew_micros
    }

    /// Resets synchronizer state on stream restart or seek.
    pub fn reset(&mut self) {
        self.has_audio_clock = false;
        self.last_audio_pts_micros = 0;
        self.last_audio_host_time_micros = 0;
        self.smoothed_skew_micros = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_no_audio_clock() {
        let mut sync = AvSynchronizer::default();
        let decision = sync.evaluate_video_frame(100_000, 50_000);
        assert_eq!(decision.action, VideoAction::PresentNow);
        assert_eq!(decision.wait_micros, 0);
    }

    #[test]
    fn test_on_time_and_waiting() {
        let mut sync = AvSynchronizer::new(SyncPreset::Balanced);

        // Audio rendered at pts 1_000_000 us at host time 500_000 us
        sync.on_audio_rendered(1_000_000, 500_000);

        // 10ms later in host time (host time = 510_000 us)
        // Effective audio PTS is 1_010_000 us.
        // Video frame at 1_015_000 us is only 5ms ahead -> within on-time window (16.6ms)
        let d1 = sync.evaluate_video_frame(1_015_000, 510_000);
        assert_eq!(d1.action, VideoAction::PresentNow);
        assert_eq!(d1.wait_micros, 0);

        // Video frame at 1_050_000 us is 40ms ahead -> should Wait
        let d2 = sync.evaluate_video_frame(1_050_000, 510_000);
        assert_eq!(d2.action, VideoAction::Wait);
        assert_eq!(d2.wait_micros, 40_000);

        // Video frame at 950_000 us is 60ms behind (> 50ms drop threshold) -> should DropLate
        let d3 = sync.evaluate_video_frame(950_000, 510_000);
        assert_eq!(d3.action, VideoAction::DropLate);
    }

    #[test]
    fn test_user_audio_offset() {
        let mut sync = AvSynchronizer::new(SyncPreset::Balanced);
        sync.on_audio_rendered(1_000_000, 500_000);

        // Add +30ms user audio offset (audio is delayed by 30ms)
        sync.set_user_audio_offset_micros(30_000);

        // Effective audio PTS becomes 1_000_000 + 30_000 = 1_030_000 us
        // Video frame at 1_030_000 us should now be PresentNow
        let d = sync.evaluate_video_frame(1_030_000, 500_000);
        assert_eq!(d.action, VideoAction::PresentNow);
        assert_eq!(d.skew_micros, 0);
    }

    #[test]
    fn test_reset() {
        let mut sync = AvSynchronizer::new(SyncPreset::Balanced);
        sync.on_audio_rendered(1_000_000, 500_000);
        sync.reset();

        let d = sync.evaluate_video_frame(1_000_000, 500_000);
        assert_eq!(d.action, VideoAction::PresentNow);
    }
}
