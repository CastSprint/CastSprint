//! CastSprint Session Manager and Clock Estimator.
//! Normative specification: `docs/architecture/PROTOCOL.md` and `AUDIO_AND_LAN.md`

use castsprint_protocol::{Heartbeat, Hello, HelloAck, HelloStatus, MAX_PAYLOAD_SIZE, VERSION};
use rand::Rng;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum ConnectionState {
    #[default]
    Disconnected = 0,
    Listening = 1,
    Handshaking = 2,
    Connected = 3,
    Reconnecting = 4,
    Closed = 5,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct SessionStats {
    pub total_bytes_received: u64,
    pub video_frames_received: u32,
    pub audio_frames_received: u32,
    pub keyframes_received: u32,
    pub dropped_frames: u32,
    pub current_fps: f64,
    pub current_bitrate_mbps: f64,
    pub last_rtt_micros: u64,
    pub estimated_clock_offset_micros: i64,
}

pub struct SessionManager {
    state: ConnectionState,
    session_pin: String,
    cert_fingerprint: String,
    session_id: u32,
    stats: SessionStats,

    last_stats_update_micros: u64,
    bytes_since_last_stats: u64,
    frames_since_last_stats: u32,
    last_sent_heartbeat_micros: u64,
}

impl Default for SessionManager {
    fn default() -> Self {
        Self::new()
    }
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            state: ConnectionState::Disconnected,
            session_pin: String::new(),
            cert_fingerprint: String::new(),
            session_id: 0,
            stats: SessionStats::default(),
            last_stats_update_micros: 0,
            bytes_since_last_stats: 0,
            frames_since_last_stats: 0,
            last_sent_heartbeat_micros: 0,
        }
    }

    /// Generates a random 6-digit numeric PIN (or uses supplied pin) and sets certificate fingerprint.
    pub fn initialize_pairing(&mut self, cert_fingerprint_sha256: &str, pin: Option<&str>) {
        self.cert_fingerprint = cert_fingerprint_sha256.to_string();
        if let Some(p) = pin {
            if !p.is_empty() {
                self.session_pin = p.to_string();
                return;
            }
        }
        let mut rng = rand::thread_rng();
        let num: u32 = rng.gen_range(100_000..=999_999);
        self.session_pin = num.to_string();
    }

    pub fn session_pin(&self) -> &str {
        &self.session_pin
    }

    pub fn certificate_fingerprint(&self) -> &str {
        &self.cert_fingerprint
    }

    pub fn state(&self) -> ConnectionState {
        self.state
    }

    pub fn set_state(&mut self, state: ConnectionState) {
        self.state = state;
    }

    pub fn session_id(&self) -> u32 {
        self.session_id
    }

    pub fn stats(&self) -> &SessionStats {
        &self.stats
    }

    /// Evaluates an incoming Hello message against version and PIN.
    /// Returns `(HelloAck, is_accepted)`.
    pub fn process_hello(&mut self, hello: &Hello, provided_pin: &str) -> (HelloAck, bool) {
        // Check version compatibility
        if hello.min_version > VERSION || hello.max_version < VERSION {
            let ack = HelloAck {
                status: HelloStatus::VersionUnsupported,
                accepted_version: VERSION,
                assigned_session_id: 0,
                max_payload_size: 0,
            };
            return (ack, false);
        }

        // Verify session pairing token (PIN) if pairing is initialized
        if !self.session_pin.is_empty() && provided_pin != self.session_pin {
            let ack = HelloAck {
                status: HelloStatus::Rejected,
                accepted_version: VERSION,
                assigned_session_id: 0,
                max_payload_size: 0,
            };
            return (ack, false);
        }

        // Assign non-zero random session ID
        let mut rng = rand::thread_rng();
        let session_id: u32 = rng.gen_range(1..=0xFFFFFFFE);
        self.session_id = session_id;

        let ack = HelloAck {
            status: HelloStatus::Accepted,
            accepted_version: VERSION,
            assigned_session_id: session_id,
            max_payload_size: MAX_PAYLOAD_SIZE as u32,
        };

        self.state = ConnectionState::Connected;
        (ack, true)
    }

    /// Creates an outbound Heartbeat packet with current timestamp.
    pub fn create_heartbeat(&mut self, now_micros: u64) -> Heartbeat {
        self.last_sent_heartbeat_micros = now_micros;
        Heartbeat {
            timestamp_micros: now_micros,
            echo_timestamp_micros: 0,
        }
    }

    /// Processes an incoming echoed Heartbeat to update RTT and clock offset.
    pub fn process_heartbeat_response(&mut self, hb: &Heartbeat, now_micros: u64) {
        if hb.echo_timestamp_micros > 0 && now_micros >= hb.echo_timestamp_micros {
            let rtt = now_micros - hb.echo_timestamp_micros;
            self.stats.last_rtt_micros = rtt;

            // Cross-device clock offset estimate:
            // offset = t_sender - (t0_receiver + RTT / 2)
            let estimated_receiver_time_at_sender = hb.echo_timestamp_micros + (rtt / 2);
            let offset = hb.timestamp_micros as i64 - estimated_receiver_time_at_sender as i64;
            self.stats.estimated_clock_offset_micros = offset;
        }
    }

    pub fn on_video_frame_received(&mut self, payload_bytes: u32, is_keyframe: bool) {
        self.stats.total_bytes_received += payload_bytes as u64;
        self.bytes_since_last_stats += payload_bytes as u64;
        self.stats.video_frames_received += 1;
        self.frames_since_last_stats += 1;
        if is_keyframe {
            self.stats.keyframes_received += 1;
        }
    }

    pub fn on_audio_frame_received(&mut self, payload_bytes: u32) {
        self.stats.total_bytes_received += payload_bytes as u64;
        self.bytes_since_last_stats += payload_bytes as u64;
        self.stats.audio_frames_received += 1;
    }

    pub fn on_frame_dropped(&mut self) {
        self.stats.dropped_frames += 1;
    }

    /// Updates rolling FPS and bitrate calculations every 500ms.
    pub fn update_periodic_stats(&mut self, now_micros: u64) {
        if self.last_stats_update_micros == 0 {
            self.last_stats_update_micros = now_micros;
            return;
        }

        let elapsed = now_micros.saturating_sub(self.last_stats_update_micros);
        if elapsed >= 500_000 {
            // 500ms
            let elapsed_sec = elapsed as f64 / 1_000_000.0;
            self.stats.current_fps = self.frames_since_last_stats as f64 / elapsed_sec;
            self.stats.current_bitrate_mbps =
                (self.bytes_since_last_stats as f64 * 8.0) / (elapsed_sec * 1_000_000.0);

            self.last_stats_update_micros = now_micros;
            self.bytes_since_last_stats = 0;
            self.frames_since_last_stats = 0;
        }
    }

    pub fn reset(&mut self) {
        self.state = ConnectionState::Disconnected;
        self.session_id = 0;
        self.stats = SessionStats::default();
        self.last_stats_update_micros = 0;
        self.bytes_since_last_stats = 0;
        self.frames_since_last_stats = 0;
        self.last_sent_heartbeat_micros = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use castsprint_protocol::CAP_VIDEO_H264;

    #[test]
    fn test_pairing_and_hello() {
        let mut sm = SessionManager::new();
        sm.initialize_pairing(
            "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855",
            Some("123456"),
        );
        assert_eq!(sm.session_pin(), "123456");
        assert_eq!(sm.state(), ConnectionState::Disconnected);

        let hello = Hello {
            min_version: 1,
            max_version: 1,
            capabilities: CAP_VIDEO_H264,
            android_api_level: 34,
            screen_width: 1080,
            screen_height: 2400,
            density_dpi: 420,
            device_name: "Pixel 8".to_string(),
            device_model: "shiba".to_string(),
        };

        // Reject on bad PIN
        let (ack_bad, ok_bad) = sm.process_hello(&hello, "654321");
        assert!(!ok_bad);
        assert_eq!(ack_bad.status, HelloStatus::Rejected);
        assert_eq!(sm.state(), ConnectionState::Disconnected);

        // Accept on valid PIN
        let (ack_good, ok_good) = sm.process_hello(&hello, "123456");
        assert!(ok_good);
        assert_eq!(ack_good.status, HelloStatus::Accepted);
        assert!(ack_good.assigned_session_id > 0);
        assert_eq!(sm.state(), ConnectionState::Connected);
    }

    #[test]
    fn test_version_incompatible() {
        let mut sm = SessionManager::new();
        sm.initialize_pairing("dummy", Some("123456"));

        let hello_future = Hello {
            min_version: 2,
            max_version: 3,
            capabilities: CAP_VIDEO_H264,
            android_api_level: 34,
            screen_width: 1080,
            screen_height: 2400,
            density_dpi: 420,
            device_name: "Future Phone".to_string(),
            device_model: "future".to_string(),
        };

        let (ack, ok) = sm.process_hello(&hello_future, "123456");
        assert!(!ok);
        assert_eq!(ack.status, HelloStatus::VersionUnsupported);
    }

    #[test]
    fn test_heartbeat_and_clock_offset() {
        let mut sm = SessionManager::new();
        sm.initialize_pairing("dummy", Some("123456"));

        let t0 = 1_000_000;
        let hb = sm.create_heartbeat(t0);
        assert_eq!(hb.timestamp_micros, t0);

        // Simulate sender echoing back t0 at sender time 5_000_000
        // Received at receiver at t1 = 1_020_000 (RTT = 20_000 us = 20ms)
        let echo = Heartbeat {
            timestamp_micros: 5_000_000,
            echo_timestamp_micros: t0,
        };
        let t1 = 1_020_000;

        sm.process_heartbeat_response(&echo, t1);
        assert_eq!(sm.stats().last_rtt_micros, 20_000);
        // Estimated receiver time at sender = 1_000_000 + 10_000 = 1_010_000
        // Offset = 5_000_000 - 1_010_000 = 3_990_000 us
        assert_eq!(sm.stats().estimated_clock_offset_micros, 3_990_000);
    }

    #[test]
    fn test_frame_stats() {
        let mut sm = SessionManager::new();
        sm.on_video_frame_received(100_000, true);
        sm.on_video_frame_received(50_000, false);
        sm.on_audio_frame_received(1_000);
        sm.on_frame_dropped();

        assert_eq!(sm.stats().video_frames_received, 2);
        assert_eq!(sm.stats().keyframes_received, 1);
        assert_eq!(sm.stats().audio_frames_received, 1);
        assert_eq!(sm.stats().dropped_frames, 1);
        assert_eq!(sm.stats().total_bytes_received, 151_000);
    }
}
