//! CastSprint Native Audio Player.
//! High-performance, low-latency audio output for Windows (WASAPI), Linux (PipeWire/ALSA), and macOS (CoreAudio).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Stream, StreamConfig};

pub struct AudioPlayer {
    is_active: Arc<AtomicBool>,
    ring_buffer: Arc<Mutex<Vec<i16>>>,
    stream: Option<Stream>,
    channels: u16,
    sample_rate: u32,
}

impl Default for AudioPlayer {
    fn default() -> Self {
        Self::new(48_000, 2)
    }
}

impl AudioPlayer {
    pub fn new(sample_rate: u32, channels: u16) -> Self {
        let is_active = Arc::new(AtomicBool::new(false));
        let ring_buffer = Arc::new(Mutex::new(Vec::with_capacity(48_000 * 2)));

        let mut player = Self {
            is_active,
            ring_buffer,
            stream: None,
            channels,
            sample_rate,
        };

        let _ = player.init_hardware_stream();
        player
    }

    fn init_hardware_stream(&mut self) -> Result<(), String> {
        let host = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or_else(|| "No default audio output device found".to_string())?;

        let config = StreamConfig {
            channels: self.channels,
            sample_rate: self.sample_rate,
            buffer_size: cpal::BufferSize::Default,
        };

        let ring_buffer_clone = Arc::clone(&self.ring_buffer);
        let is_active_clone = Arc::clone(&self.is_active);

        let err_fn = |err| eprintln!("[AUDIO-ERROR] Device stream error: {}", err);

        let stream = device
            .build_output_stream(
                config,
                move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                    if !is_active_clone.load(Ordering::SeqCst) {
                        for sample in data.iter_mut() {
                            *sample = 0.0;
                        }
                        return;
                    }

                    let mut buf = ring_buffer_clone.lock().unwrap();
                    for sample in data.iter_mut() {
                        if !buf.is_empty() {
                            let pcm16 = buf.remove(0);
                            *sample = pcm16 as f32 / 32768.0;
                        } else {
                            *sample = 0.0;
                        }
                    }
                },
                err_fn,
                Some(Duration::from_millis(50)),
            )
            .map_err(|e| format!("Failed to build output stream: {}", e))?;

        stream
            .play()
            .map_err(|e| format!("Failed to start audio stream: {}", e))?;

        self.stream = Some(stream);
        self.is_active.store(true, Ordering::SeqCst);
        Ok(())
    }

    /// Feeds raw PCM 16-bit interleaved audio samples into playback queue.
    pub fn play_pcm_frame(&mut self, pcm_data: &[u8]) {
        if pcm_data.len() < 2 {
            return;
        }

        let mut samples = Vec::with_capacity(pcm_data.len() / 2);
        for chunk in pcm_data.chunks_exact(2) {
            let sample = i16::from_le_bytes([chunk[0], chunk[1]]);
            samples.push(sample);
        }

        if let Ok(mut buf) = self.ring_buffer.lock() {
            // Keep buffer bounded (~100ms at 48kHz stereo = 9,600 samples) to prevent latency buildup
            if buf.len() > 9600 {
                buf.drain(0..4800); // Drop older samples to maintain lip-sync
            }
            buf.extend(samples);
        }
    }

    pub fn reconfigure(&mut self, sample_rate: u32, channels: u16) {
        if self.sample_rate != sample_rate || self.channels != channels {
            self.sample_rate = sample_rate;
            self.channels = channels;
            self.stream = None;
            let _ = self.init_hardware_stream();
        }
    }

    pub fn stop(&mut self) {
        self.is_active.store(false, Ordering::SeqCst);
        self.stream = None;
        if let Ok(mut buf) = self.ring_buffer.lock() {
            buf.clear();
        }
    }
}
