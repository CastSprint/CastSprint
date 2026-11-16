//! CastSprint Native Display Viewport Window.
//! Hardware-presented desktop window for Windows (Win32), Linux (Wayland/X11), and macOS (AppKit).
//! High-performance gaming viewport with interactive HUD, thermal cooling mode, lossless screenshot, and mouse touch input.
//! Normative specification: `docs/architecture/SCREEN_MIRRORING.md` and `OBS_OUTPUT.md`

use std::num::NonZeroU32;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use castsprint_core::adb::AdbManager;
use castsprint_core::media::save_bmp_screenshot;
use softbuffer::{Context, Surface};
use winit::application::ApplicationHandler;
use winit::dpi::{LogicalPosition, LogicalSize};
use winit::event::{ElementState, KeyEvent, MouseButton, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::keyboard::{Key, NamedKey};
use winit::window::{Fullscreen, Window, WindowId};

/// Shared state synchronized between the network receiver thread and the GUI window.
#[derive(Debug, Clone)]
pub struct ViewportState {
    pub device_name: String,
    pub device_model: String,
    pub current_fps: f64,
    pub current_bitrate_mbps: f64,
    pub rtt_ms: f64,
    pub clock_offset_us: i64,
    pub dropped_frames: u64,
    pub phone_width: u32,
    pub phone_height: u32,
    pub is_recording: bool,
    pub frames_recorded: u64,
    pub cooling_mode: bool,
    pub hud_visible: bool,
    pub sync_preset: String,
    pub status_message: String,
    pub status_expiry: Instant,
}

impl Default for ViewportState {
    fn default() -> Self {
        Self {
            device_name: "Mobile Device".to_string(),
            device_model: "CastSprint".to_string(),
            current_fps: 60.0,
            current_bitrate_mbps: 0.0,
            rtt_ms: 0.0,
            clock_offset_us: 0,
            dropped_frames: 0,
            phone_width: 1080,
            phone_height: 2400,
            is_recording: false,
            frames_recorded: 0,
            cooling_mode: false,
            hud_visible: true,
            sync_preset: "BALANCED".to_string(),
            status_message: "READY - PRESS H TO HIDE HUD, C FOR COOLING, S FOR SCREENSHOT".to_string(),
            status_expiry: Instant::now() + Duration::from_secs(6),
        }
    }
}

pub struct DisplayWindowApp {
    window: Option<Arc<Window>>,
    surface: Option<Surface<Arc<Window>, Arc<Window>>>,
    context: Option<Context<Arc<Window>>>,
    is_running: Arc<AtomicBool>,
    pairing_pin: String,
    state: Arc<Mutex<ViewportState>>,
    adb: Arc<AdbManager>,
    cursor_pos: LogicalPosition<f64>,
    render_width: u32,
    render_height: u32,
    frame_counter: u64,
}

impl DisplayWindowApp {
    pub fn new(
        is_running: Arc<AtomicBool>,
        pairing_pin: String,
        state: Arc<Mutex<ViewportState>>,
    ) -> Self {
        Self {
            window: None,
            surface: None,
            context: None,
            is_running,
            pairing_pin,
            state,
            adb: Arc::new(AdbManager::new()),
            cursor_pos: LogicalPosition::new(0.0, 0.0),
            render_width: 1280,
            render_height: 720,
            frame_counter: 0,
        }
    }

    fn trigger_screenshot(state: &Arc<Mutex<ViewportState>>, width: u32, height: u32, buffer: &[u32]) {
        let pictures_dir = std::env::var("USERPROFILE")
            .or_else(|_| std::env::var("HOME"))
            .map(|h| PathBuf::from(h).join("Pictures").join("CastSprint"))
            .unwrap_or_else(|_| PathBuf::from("screenshots"));

        let timestamp = chrono_or_simple_timestamp();
        let shot_path = pictures_dir.join(format!("CastSprint_{}.bmp", timestamp));

        match save_bmp_screenshot(&shot_path, width, height, buffer) {
            Ok(()) => {
                println!("[SCREENSHOT] Saved lossless image: {}", shot_path.display());
                if let Ok(mut st) = state.lock() {
                    st.status_message = format!("SCREENSHOT SAVED: {}", shot_path.file_name().unwrap_or_default().to_string_lossy());
                    st.status_expiry = Instant::now() + Duration::from_secs(4);
                }
            }
            Err(e) => {
                eprintln!("[SCREENSHOT-ERROR] Failed to save screenshot: {}", e);
            }
        }
    }

    fn toggle_cooling_mode(&self) {
        let (new_cooling, adb) = {
            if let Ok(mut st) = self.state.lock() {
                st.cooling_mode = !st.cooling_mode;
                let is_on = st.cooling_mode;
                st.status_message = if is_on {
                    "COOLING MODE: ACTIVE (PHONE SCREEN DIMMED TO SAVE HEAT & BATTERY)".to_string()
                } else {
                    "COOLING MODE: OFF (BRIGHTNESS RESTORED)".to_string()
                };
                st.status_expiry = Instant::now() + Duration::from_secs(4);
                (is_on, Arc::clone(&self.adb))
            } else {
                return;
            }
        };

        std::thread::spawn(move || {
            let _ = adb.set_screen_cooling_mode(None, new_cooling);
        });
    }

    fn forward_touch_tap(&self, win_w: u32, win_h: u32) {
        let (phone_w, phone_h) = {
            if let Ok(st) = self.state.lock() {
                (st.phone_width.max(1), st.phone_height.max(1))
            } else {
                (1080, 2400)
            }
        };

        let norm_x = (self.cursor_pos.x / win_w as f64).clamp(0.0, 1.0);
        let norm_y = (self.cursor_pos.y / win_h as f64).clamp(0.0, 1.0);

        let touch_x = (norm_x * phone_w as f64) as u32;
        let touch_y = (norm_y * phone_h as f64) as u32;

        let adb = Arc::clone(&self.adb);
        std::thread::spawn(move || {
            let _ = adb.send_touch_tap(None, touch_x, touch_y);
        });
    }
}

impl ApplicationHandler for DisplayWindowApp {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }

        let attributes = Window::default_attributes()
            .with_title(format!(
                "CastSprint Studio Viewport — PIN: {} [Low-Latency Gaming]",
                self.pairing_pin
            ))
            .with_inner_size(LogicalSize::new(self.render_width, self.render_height))
            .with_min_inner_size(LogicalSize::new(480, 320));

        let window = match event_loop.create_window(attributes) {
            Ok(w) => Arc::new(w),
            Err(e) => {
                eprintln!("[GUI-ERROR] Could not create native window: {}", e);
                return;
            }
        };

        let context = match Context::new(Arc::clone(&window)) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("[GUI-ERROR] Could not initialize softbuffer context: {}", e);
                return;
            }
        };

        let surface = match Surface::new(&context, Arc::clone(&window)) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("[GUI-ERROR] Could not initialize softbuffer surface: {}", e);
                return;
            }
        };

        self.window = Some(window);
        self.context = Some(context);
        self.surface = Some(surface);
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => {
                self.is_running.store(false, Ordering::SeqCst);
                event_loop.exit();
            }
            WindowEvent::CursorMoved { position, .. } => {
                self.cursor_pos = position.to_logical(1.0);
            }
            WindowEvent::MouseInput {
                state: ElementState::Pressed,
                button: MouseButton::Left,
                ..
            } => {
                if let Some(ref w) = self.window {
                    let size = w.inner_size();
                    self.forward_touch_tap(size.width, size.height);
                }
            }
            WindowEvent::KeyboardInput {
                event:
                    KeyEvent {
                        logical_key,
                        state: ElementState::Pressed,
                        ..
                    },
                ..
            } => match logical_key {
                Key::Named(NamedKey::F11) => {
                    if let Some(ref w) = self.window {
                        let is_fullscreen = w.fullscreen().is_some();
                        w.set_fullscreen(if is_fullscreen {
                            None
                        } else {
                            Some(Fullscreen::Borderless(None))
                        });
                    }
                }
                Key::Named(NamedKey::Escape) => {
                    if let Some(ref w) = self.window {
                        if w.fullscreen().is_some() {
                            w.set_fullscreen(None);
                        }
                    }
                }
                Key::Character(ref ch) => {
                    if ch.eq_ignore_ascii_case("h") {
                        if let Ok(mut st) = self.state.lock() {
                            st.hud_visible = !st.hud_visible;
                        }
                    } else if ch.eq_ignore_ascii_case("c") {
                        self.toggle_cooling_mode();
                    } else if ch.eq_ignore_ascii_case("s") {
                        if let Some(ref w) = self.window {
                            let size = w.inner_size();
                            let state_ref = Arc::clone(&self.state);
                            if let Some(ref mut surface) = self.surface {
                                if let Ok(buffer) = surface.buffer_mut() {
                                    Self::trigger_screenshot(&state_ref, size.width, size.height, &buffer);
                                }
                            }
                        }
                    } else if ch == "1" {
                        if let Ok(mut st) = self.state.lock() {
                            st.sync_preset = "LOW-LATENCY (10MS)".to_string();
                            st.status_message = "AV SYNC: ULTRA LOW-LATENCY PRESET (10MS)".to_string();
                            st.status_expiry = Instant::now() + Duration::from_secs(3);
                        }
                    } else if ch == "2" {
                        if let Ok(mut st) = self.state.lock() {
                            st.sync_preset = "BALANCED (25MS)".to_string();
                            st.status_message = "AV SYNC: BALANCED GAMING PRESET (25MS)".to_string();
                            st.status_expiry = Instant::now() + Duration::from_secs(3);
                        }
                    } else if ch == "3" {
                        if let Ok(mut st) = self.state.lock() {
                            st.sync_preset = "HIGH-QUALITY (50MS)".to_string();
                            st.status_message = "AV SYNC: HIGH-QUALITY CINEMATIC PRESET (50MS)".to_string();
                            st.status_expiry = Instant::now() + Duration::from_secs(3);
                        }
                    }
                }
                _ => {}
            },
            WindowEvent::RedrawRequested => {
                self.render_viewport();
            }
            _ => {}
        }
    }

    fn about_to_wait(&mut self, _event_loop: &ActiveEventLoop) {
        if !self.is_running.load(Ordering::SeqCst) {
            return;
        }
        if let Some(ref w) = self.window {
            w.request_redraw();
        }
    }
}

impl DisplayWindowApp {
    fn render_viewport(&mut self) {
        let (surface, window) = match (self.surface.as_mut(), self.window.as_ref()) {
            (Some(s), Some(w)) => (s, w),
            _ => return,
        };

        let size = window.inner_size();
        let width = size.width.max(1);
        let height = size.height.max(1);

        if surface
            .resize(
                NonZeroU32::new(width).unwrap(),
                NonZeroU32::new(height).unwrap(),
            )
            .is_err()
        {
            return;
        }

        let mut buffer = match surface.buffer_mut() {
            Ok(b) => b,
            Err(_) => return,
        };

        self.frame_counter += 1;

        // Dark gaming viewport canvas: 0x0012141A
        let bg_color = 0x0012141A;
        buffer.fill(bg_color);

        let state_snapshot = self.state.lock().unwrap().clone();

        // Render HUD overlay if visible (streamers can hide it with 'H' for clean OBS capture)
        if state_snapshot.hud_visible {
            let buf_w = width as usize;

            // 1. Top Bar Background (Dark modern glass: 0x001A1D24)
            let top_bar_height = (36).min(height as usize);
            for y in 0..top_bar_height {
                let start = y * buf_w;
                let end = (start + buf_w).min(buffer.len());
                buffer[start..end].fill(0x001A1D24);
            }
            // Accent divider line (Teal Cyan: 0x0000BCD4)
            if top_bar_height < height as usize {
                let line_start = top_bar_height * buf_w;
                let line_end = (line_start + buf_w).min(buffer.len());
                buffer[line_start..line_end].fill(0x0000BCD4);
            }

            // Top Bar Text & Telemetry Badges
            let title = format!(
                "CASTSPRINT | {} | {:.1} FPS | {:.2} MBPS | {:.1} MS",
                state_snapshot.device_model.to_uppercase(),
                state_snapshot.current_fps,
                state_snapshot.current_bitrate_mbps,
                state_snapshot.rtt_ms
            );
            draw_string(&mut buffer, buf_w, 12, 10, &title, 0x00ECEFF1, 2);

            // Badges on Top Right
            let mut right_x = (buf_w.saturating_sub(180)) as usize;
            if state_snapshot.cooling_mode {
                draw_string(&mut buffer, buf_w, right_x, 10, "[COOLING: ON]", 0x0026A69A, 2);
                right_x = right_x.saturating_sub(160);
            }
            if state_snapshot.is_recording {
                let rec_color = if (self.frame_counter / 30) % 2 == 0 {
                    0x00E53935 // Pulsing red
                } else {
                    0x00EF9A9A
                };
                let rec_text = format!("[● REC {}F]", state_snapshot.frames_recorded);
                draw_string(&mut buffer, buf_w, right_x, 10, &rec_text, rec_color, 2);
            }

            // 2. Bottom Status & Hotkey Helper Bar
            let bottom_bar_height = 28;
            if height as usize > bottom_bar_height {
                let bottom_y = (height as usize) - bottom_bar_height;
                for y in bottom_y..(height as usize) {
                    let start = y * buf_w;
                    let end = (start + buf_w).min(buffer.len());
                    buffer[start..end].fill(0x0015181F);
                }

                // Hotkey hints
                let hints = "[F11] FULLSCREEN   [H] HIDE HUD   [C] COOLING   [R] RECORD   [S] SCREENSHOT   [1-3] PRESET";
                draw_string(&mut buffer, buf_w, 12, bottom_y + 7, hints, 0x0078909C, 1);
            }

            // 3. Transient Status Message Notification Toast
            if Instant::now() < state_snapshot.status_expiry && !state_snapshot.status_message.is_empty() {
                let toast_y = (height as usize) / 2 - 20;
                let toast_text = &state_snapshot.status_message;
                let toast_w = (toast_text.len() * 12) + 24;
                let toast_x = buf_w.saturating_sub(toast_w) / 2;

                // Toast background
                for ty in toast_y..(toast_y + 36).min(height as usize) {
                    let start = ty * buf_w + toast_x;
                    let end = (start + toast_w).min(buffer.len());
                    buffer[start..end].fill(0x00263238);
                }
                draw_string(&mut buffer, buf_w, toast_x + 12, toast_y + 10, toast_text, 0x0080DEEA, 2);
            }
        }

        let _ = buffer.present();
    }
}

/// Runs the native GUI window event loop on the main thread.
pub fn run_gui_window(
    is_running: Arc<AtomicBool>,
    pairing_pin: String,
    state: Arc<Mutex<ViewportState>>,
) {
    let event_loop = match EventLoop::new() {
        Ok(el) => el,
        Err(e) => {
            eprintln!("[GUI-ERROR] Could not start event loop: {}", e);
            return;
        }
    };
    event_loop.set_control_flow(ControlFlow::Poll);

    let mut app = DisplayWindowApp::new(is_running, pairing_pin, state);
    let _ = event_loop.run_app(&mut app);
}

// =========================================================================
// Embedded High-Performance 5x7 ASCII Bitmap Font Engine (Zero Dependencies)
// =========================================================================

fn get_glyph(c: char) -> [u8; 7] {
    match c.to_ascii_uppercase() {
        '0' => [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
        '1' => [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
        '2' => [0x0E, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F],
        '3' => [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
        '4' => [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
        '5' => [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
        '6' => [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
        '7' => [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
        '8' => [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
        '9' => [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
        'A' => [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        'B' => [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
        'C' => [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
        'D' => [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C],
        'E' => [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
        'F' => [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
        'G' => [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
        'H' => [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        'I' => [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
        'J' => [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
        'K' => [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
        'L' => [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
        'M' => [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
        'N' => [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11],
        'O' => [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        'P' => [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
        'Q' => [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
        'R' => [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
        'S' => [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
        'T' => [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
        'U' => [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        'V' => [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
        'W' => [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A],
        'X' => [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
        'Y' => [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04],
        'Z' => [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
        ':' => [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],
        '.' => [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
        '-' => [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
        '+' => [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00],
        '[' => [0x0E, 0x08, 0x08, 0x08, 0x08, 0x08, 0x0E],
        ']' => [0x0E, 0x02, 0x02, 0x02, 0x02, 0x02, 0x0E],
        '/' => [0x01, 0x02, 0x04, 0x08, 0x10, 0x00, 0x00],
        '%' => [0x19, 0x1A, 0x04, 0x08, 0x16, 0x13, 0x00],
        '|' => [0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
        _ => [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    }
}

fn draw_char(
    buffer: &mut [u32],
    buf_width: usize,
    x: usize,
    y: usize,
    c: char,
    color: u32,
    scale: usize,
) {
    let glyph = get_glyph(c);
    let buf_len = buffer.len();
    for (row_idx, &row_bits) in glyph.iter().enumerate() {
        for col_idx in 0..5 {
            if (row_bits & (1 << (4 - col_idx))) != 0 {
                for sy in 0..scale {
                    for sx in 0..scale {
                        let px = x + col_idx * scale + sx;
                        let py = y + row_idx * scale + sy;
                        let idx = py * buf_width + px;
                        if idx < buf_len && px < buf_width {
                            buffer[idx] = color;
                        }
                    }
                }
            }
        }
    }
}

fn draw_string(
    buffer: &mut [u32],
    buf_width: usize,
    x: usize,
    y: usize,
    text: &str,
    color: u32,
    scale: usize,
) {
    let char_width = 6 * scale;
    for (i, c) in text.chars().enumerate() {
        draw_char(buffer, buf_width, x + i * char_width, y, c, color, scale);
    }
}

fn chrono_or_simple_timestamp() -> String {
    use std::time::SystemTime;
    let duration = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default();
    format!("{}_{:03}", duration.as_secs(), duration.subsec_millis())
}
