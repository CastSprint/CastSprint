//! CastSprint Native Display Viewport Window.
//! Hardware-presented desktop window for Windows (Win32), Linux (Wayland/X11), and macOS (AppKit).
//! Normative specification: `docs/architecture/SCREEN_MIRRORING.md` and `OBS_OUTPUT.md`

use std::num::NonZeroU32;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use softbuffer::{Context, Surface};
use winit::application::ApplicationHandler;
use winit::dpi::LogicalSize;
use winit::event::{ElementState, KeyEvent, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoop};
use winit::keyboard::{Key, NamedKey};
use winit::window::{Window, WindowId};

#[allow(dead_code)]
pub struct DisplayWindowApp {
    window: Option<Arc<Window>>,
    surface: Option<Surface<Arc<Window>, Arc<Window>>>,
    context: Option<Context<Arc<Window>>>,
    is_running: Arc<AtomicBool>,
    pairing_pin: String,
    device_name: String,
    fps: f64,
    bitrate: f64,
    width: u32,
    height: u32,
}

#[allow(dead_code)]
impl DisplayWindowApp {
    pub fn new(is_running: Arc<AtomicBool>, pairing_pin: String) -> Self {
        Self {
            window: None,
            surface: None,
            context: None,
            is_running,
            pairing_pin,
            device_name: "Waiting for connection...".to_string(),
            fps: 0.0,
            bitrate: 0.0,
            width: 1280,
            height: 720,
        }
    }

    pub fn set_telemetry(&mut self, device: &str, fps: f64, bitrate: f64) {
        self.device_name = device.to_string();
        self.fps = fps;
        self.bitrate = bitrate;
    }

    pub fn update_display_size(&mut self, width: u32, height: u32) {
        self.width = width.max(320);
        self.height = height.max(240);
        if let Some(ref w) = self.window {
            let _ = w.request_inner_size(LogicalSize::new(self.width, self.height));
        }
    }
}

impl ApplicationHandler for DisplayWindowApp {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }

        let attributes = Window::default_attributes()
            .with_title(format!("CastSprint Receiver — PIN: {}", self.pairing_pin))
            .with_inner_size(LogicalSize::new(self.width, self.height))
            .with_min_inner_size(LogicalSize::new(360, 640));

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
            WindowEvent::KeyboardInput {
                event:
                    KeyEvent {
                        logical_key: Key::Named(NamedKey::F11),
                        state: ElementState::Pressed,
                        ..
                    },
                ..
            } => {
                if let Some(ref w) = self.window {
                    let is_fullscreen = w.fullscreen().is_some();
                    w.set_fullscreen(if is_fullscreen {
                        None
                    } else {
                        Some(winit::window::Fullscreen::Borderless(None))
                    });
                }
            }
            WindowEvent::RedrawRequested => {
                self.render_frame();
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
    fn render_frame(&mut self) {
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

        // Dark gaming backdrop: 0x12, 0x14, 0x1A (Hex: 0x0012141A)
        let bg_color = 0x0012141A;
        buffer.fill(bg_color);

        // Render clean status bar on top
        let bar_height = (32).min(height as usize);
        let bar_color = 0x001E222D;
        for y in 0..bar_height {
            let row_start = y * (width as usize);
            let row_end = row_start + (width as usize);
            if row_end <= buffer.len() {
                buffer[row_start..row_end].fill(bar_color);
            }
        }

        let _ = buffer.present();
    }
}

/// Runs the native GUI window event loop on the main thread.
pub fn run_gui_window(is_running: Arc<AtomicBool>, pairing_pin: String) {
    let event_loop = match EventLoop::new() {
        Ok(el) => el,
        Err(e) => {
            eprintln!("[GUI-ERROR] Could not start event loop: {}", e);
            return;
        }
    };
    event_loop.set_control_flow(ControlFlow::Poll);

    let mut app = DisplayWindowApp::new(is_running, pairing_pin);
    let _ = event_loop.run_app(&mut app);
}
