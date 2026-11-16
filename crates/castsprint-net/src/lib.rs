//! CastSprint High-Performance Low-Latency TCP Transport and Framing Engine.
//! Normative specification: `docs/architecture/PROTOCOL.md` and `AUDIO_AND_LAN.md`

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use castsprint_protocol::*;
use castsprint_session::{ConnectionState, SessionManager, SessionStats};

#[derive(Debug, Clone)]
pub enum NetEvent {
    Listening(u16),
    Connected(SocketAddr),
    HandshakeComplete {
        session_id: u32,
        device_name: String,
        device_model: String,
    },
    VideoConfig(VideoConfig),
    VideoFrame(VideoFrame),
    AudioConfig(AudioConfig),
    AudioFrame(AudioFrame),
    DisplayChanged(DisplayChanged),
    HeartbeatReceived { rtt_micros: u64, clock_offset_micros: i64 },
    Disconnected,
    Error(String),
}

fn now_micros() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_micros() as u64
}

pub struct LanServer {
    is_running: Arc<AtomicBool>,
    server_thread: Option<JoinHandle<()>>,
    session_manager: Arc<Mutex<SessionManager>>,
    event_receiver: Option<Receiver<NetEvent>>,
}

impl Default for LanServer {
    fn default() -> Self {
        Self::new()
    }
}

impl LanServer {
    pub fn new() -> Self {
        Self {
            is_running: Arc::new(AtomicBool::new(false)),
            server_thread: None,
            session_manager: Arc::new(Mutex::new(SessionManager::new())),
            event_receiver: None,
        }
    }

    pub fn session_pin(&self) -> String {
        self.session_manager.lock().unwrap().session_pin().to_string()
    }

    pub fn state(&self) -> ConnectionState {
        self.session_manager.lock().unwrap().state()
    }

    pub fn stats(&self) -> SessionStats {
        self.session_manager.lock().unwrap().stats().clone()
    }

    pub fn is_running(&self) -> bool {
        self.is_running.load(Ordering::SeqCst)
    }

    pub fn take_event_receiver(&mut self) -> Option<Receiver<NetEvent>> {
        self.event_receiver.take()
    }

    /// Starts listening on port with optional pairing PIN.
    pub fn start(&mut self, port: u16, pin: Option<&str>) -> std::io::Result<Receiver<NetEvent>> {
        self.stop();

        {
            let mut sm = self.session_manager.lock().unwrap();
            sm.initialize_pairing("SHA256_FINGERPRINT", pin);
            sm.set_state(ConnectionState::Listening);
        }

        let (tx, rx) = channel::<NetEvent>();
        let is_running = Arc::clone(&self.is_running);
        is_running.store(true, Ordering::SeqCst);

        let session_mgr = Arc::clone(&self.session_manager);

        let listener = TcpListener::bind(format!("0.0.0.0:{}", port))?;
        listener.set_nonblocking(true)?;

        let _ = tx.send(NetEvent::Listening(port));

        let handle = thread::spawn(move || {
            while is_running.load(Ordering::SeqCst) {
                match listener.accept() {
                    Ok((stream, peer_addr)) => {
                        let _ = stream.set_nodelay(true);
                        let _ = stream.set_read_timeout(Some(Duration::from_millis(100)));
                        let _ = stream.set_write_timeout(Some(Duration::from_millis(500)));

                        let _ = tx.send(NetEvent::Connected(peer_addr));
                        Self::handle_connection(
                            stream,
                            Arc::clone(&is_running),
                            Arc::clone(&session_mgr),
                            &tx,
                        );
                        let _ = tx.send(NetEvent::Disconnected);
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(10));
                    }
                    Err(_) => {
                        thread::sleep(Duration::from_millis(10));
                    }
                }
            }
        });

        self.server_thread = Some(handle);
        Ok(rx)
    }

    fn handle_connection(
        mut stream: TcpStream,
        is_running: Arc<AtomicBool>,
        session_mgr: Arc<Mutex<SessionManager>>,
        tx: &Sender<NetEvent>,
    ) {
        let mut header_buf = [0u8; HEADER_SIZE];
        let mut payload_buf = Vec::with_capacity(64 * 1024);
        let mut send_seq = 0u32;
        let mut last_heartbeat_time = now_micros();

        while is_running.load(Ordering::SeqCst) {
            // Check heartbeat timer (every 1 second)
            let now = now_micros();
            if now.saturating_sub(last_heartbeat_time) >= 1_000_000 {
                last_heartbeat_time = now;
                let hb = session_mgr.lock().unwrap().create_heartbeat(now);
                let session_id = session_mgr.lock().unwrap().session_id();
                let mut out_bytes = Vec::new();
                if encode_message(session_id, send_seq, &Payload::Heartbeat(hb), &mut out_bytes).is_ok() {
                    send_seq = send_seq.wrapping_add(1);
                    if stream.write_all(&out_bytes).is_err() {
                        break;
                    }
                }
            }

            // Read 24-byte header
            match stream.read_exact(&mut header_buf) {
                Ok(()) => {
                    let header = match decode_header(&header_buf) {
                        Ok(h) => h,
                        Err(e) => {
                            let _ = tx.send(NetEvent::Error(format!("Header decode error: {:?}", e)));
                            break;
                        }
                    };

                    let p_len = header.payload_length as usize;
                    if p_len > header.msg_type.max_payload_size() {
                        let _ = tx.send(NetEvent::Error("Payload limit exceeded".into()));
                        break;
                    }

                    payload_buf.resize(p_len, 0);
                    if stream.read_exact(&mut payload_buf).is_err() {
                        break;
                    }

                    // Compose full message slice
                    let mut full_bytes = Vec::with_capacity(HEADER_SIZE + p_len);
                    full_bytes.extend_from_slice(&header_buf);
                    full_bytes.extend_from_slice(&payload_buf);

                    let (msg, _) = match decode_message(&full_bytes) {
                        Ok(m) => m,
                        Err(e) => {
                            let _ = tx.send(NetEvent::Error(format!("Message decode error: {:?}", e)));
                            break;
                        }
                    };

                    // Process payload
                    match msg.payload {
                        Payload::Hello(hello) => {
                            let mut sm = session_mgr.lock().unwrap();
                            let pin = sm.session_pin().to_string();
                            let (ack, accepted) = sm.process_hello(&hello, &pin);

                            let mut ack_bytes = Vec::new();
                            if encode_message(ack.assigned_session_id, send_seq, &Payload::HelloAck(ack.clone()), &mut ack_bytes).is_ok() {
                                send_seq = send_seq.wrapping_add(1);
                                let _ = stream.write_all(&ack_bytes);
                            }

                            if accepted {
                                let _ = tx.send(NetEvent::HandshakeComplete {
                                    session_id: ack.assigned_session_id,
                                    device_name: hello.device_name,
                                    device_model: hello.device_model,
                                });
                            } else {
                                break;
                            }
                        }
                        Payload::VideoConfig(vc) => {
                            let _ = tx.send(NetEvent::VideoConfig(vc));
                        }
                        Payload::VideoFrame(vf) => {
                            let is_kf = (vf.frame_flags & FRAME_KEYFRAME) != 0;
                            let p_size = vf.data.len() as u32;
                            {
                                let mut sm = session_mgr.lock().unwrap();
                                sm.on_video_frame_received(p_size, is_kf);
                                sm.update_periodic_stats(now_micros());
                            }
                            let _ = tx.send(NetEvent::VideoFrame(vf));
                        }
                        Payload::AudioConfig(ac) => {
                            let _ = tx.send(NetEvent::AudioConfig(ac));
                        }
                        Payload::AudioFrame(af) => {
                            let p_size = af.data.len() as u32;
                            {
                                let mut sm = session_mgr.lock().unwrap();
                                sm.on_audio_frame_received(p_size);
                                sm.update_periodic_stats(now_micros());
                            }
                            let _ = tx.send(NetEvent::AudioFrame(af));
                        }
                        Payload::DisplayChanged(dc) => {
                            let _ = tx.send(NetEvent::DisplayChanged(dc));
                        }
                        Payload::Heartbeat(hb) => {
                            let now = now_micros();
                            let mut sm = session_mgr.lock().unwrap();
                            sm.process_heartbeat_response(&hb, now);
                            let rtt = sm.stats().last_rtt_micros;
                            let offset = sm.stats().estimated_clock_offset_micros;
                            let _ = tx.send(NetEvent::HeartbeatReceived {
                                rtt_micros: rtt,
                                clock_offset_micros: offset,
                            });
                        }
                        Payload::Disconnect(_) => {
                            break;
                        }
                        _ => {}
                    }
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(2));
                }
                Err(_) => {
                    break;
                }
            }
        }

        session_mgr.lock().unwrap().reset();
    }

    pub fn stop(&mut self) {
        self.is_running.store(false, Ordering::SeqCst);
        if let Some(h) = self.server_thread.take() {
            let _ = h.join();
        }
        self.session_manager.lock().unwrap().reset();
    }
}

impl Drop for LanServer {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lan_server_lifecycle() {
        let mut server = LanServer::new();
        let port = 27199; // test port
        let rx = server.start(port, Some("654321")).expect("Failed to start server");
        assert!(server.is_running());
        assert_eq!(server.session_pin(), "654321");

        let event = rx.recv_timeout(Duration::from_millis(500)).expect("No listening event");
        match event {
            NetEvent::Listening(p) => assert_eq!(p, port),
            _ => panic!("Expected NetEvent::Listening"),
        }

        server.stop();
        assert!(!server.is_running());
    }
}
