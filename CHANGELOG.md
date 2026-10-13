# Changelog

All notable changes to CastSprint are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.0-beta] - 2026-10-14

### Added
- **Windows Gaming Application UI (`apps/windows/`)**:
  - Native Win32 + Direct3D 11 multi-screen interface with dark-first theme and electric blue/cyan (`#00E5FF`) accents.
  - Six distinct application screens:
    1. **Home / Connection Screen**: USB & Wi-Fi connection tabs, status indicator, pairing PIN display, one-click start.
    2. **Gaming View**: Direct3D 11 rendering surface, aspect-ratio preservation, clean stats HUD, borderless fullscreen (`F11`).
    3. **Stream Settings**: Resolution, target FPS, bitrate controls, and low-latency/balanced presets.
    4. **Recording / Replay**: Direct MP4 passthrough recording with elapsed timer and instant start/stop toggle (`R`).
    5. **Performance & Diagnostics**: Real-time FPS, frame latency, jitter, bitrate, dropped frame counters, and AV sync drift.
    6. **Settings & Shortcuts**: Configurable hotkeys, autoconnect options, WASAPI audio device selection, and version metadata.
  - Hotkey support: `F11` (borderless fullscreen), `R` (recording toggle), `M` (mute toggle), `Up`/`Down` (volume adjust), `[`/`]` (audio sync calibration), `1`-`6` (screen navigation).
  - High-DPI awareness, double-buffered GDI dashboard, and smooth window transitions.
  - Windows version metadata resource (`resources/version.rc`) and custom branding icon (`resources/app.ico`).
- **Android Application Polish & Branding (`apps/android/`)**:
  - Embedded CastSprint branding logo (`castsprint_logo.png`).
  - Edge-to-edge layout with full system window insets support (status bars and navigation bars).
  - Quick connection guidance card for both USB debugging and Wi-Fi pairing workflows.
  - Active streaming indicator with live bitrate, FPS, and connection state.
  - Quick stream presets: Low Latency (720p 60fps), Balanced (1080p 60fps), High Quality (Native 60fps), and Custom.
  - In-app Troubleshooting & FAQ modal dialog with actionable recovery steps.
- **OBS Studio Livestreaming Support**:
  - Dedicated OBS setup documentation ([`docs/OBS_GUIDE.md`](docs/OBS_GUIDE.md)) covering Window Capture (WGC flip-model), Game Capture, application audio routing, and low-latency encoder settings.
- **Production Packaging & Release Engineering**:
  - Native Windows x64 Inno Setup 6 installer script ([`installer/castsprint_installer.iss`](installer/castsprint_installer.iss)) with firewall rule automation and desktop shortcuts.
  - Google Play Store store listing asset document ([`docs/distribution/PLAY_STORE_LISTING.md`](docs/distribution/PLAY_STORE_LISTING.md)).
  - End-to-end pre-release verification checklist ([`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md)).
- **Documentation**:
  - USB connection guide with ADB reverse and driver troubleshooting ([`docs/USB_CONNECTION.md`](docs/USB_CONNECTION.md)).
  - Local Wi-Fi pairing and TLS certificate pinning guide ([`docs/WIFI_CONNECTION.md`](docs/WIFI_CONNECTION.md)).
  - Comprehensive troubleshooting matrix ([`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)).
  - Latency profiling and measurement methodology ([`docs/PERFORMANCE.md`](docs/PERFORMANCE.md)).
  - Privacy policy and Free Forever declaration ([`docs/PRIVACY.md`](docs/PRIVACY.md)).

### Changed
- Refactored `MainWindow` in Windows client to host dedicated render surface for Direct3D 11 while retaining high-performance dashboard rendering.
- Standardized window title to `CastSprint — Gaming Screen Mirroring` for effortless OBS Window Capture hook detection.

---

## [0.1.5] - 2026-10-14

### Added
- **Android Audio Streaming Engine**:
  - Real-time internal game audio capture via `AudioPlaybackCapture` (Android 10+).
  - MediaCodec hardware AAC-LC encoder (48 kHz stereo, 128 kbps).
  - Strict zero-mic permission policy (`android.permission.RECORD_AUDIO` used exclusively for playback loopback).
- **Secure LAN / Wi-Fi Mirroring**:
  - SChannel TLS 1.3 server implementation on Windows (`LanServer`).
  - Android TLS client with SHA-256 certificate pinning (`TlsPinningSocketFactory`).
  - Local mDNS network discovery via Android `NsdManager` (`_castsprint._tcp`).
  - 4-digit pairing PIN verification for untrusted local subnets.
- **Audio/Video Synchronization (`native/sync`)**:
  - `AvSynchronizer` engine using linear regression and monotonic presentation timestamps.
  - Sub-millisecond drift compensation and adjustable user audio delay offset (`[`/`]`).
- **Windows Audio Playback (`apps/windows/audio`)**:
  - Low-latency WASAPI shared-mode playback engine (`AudioPlayer`).
  - Microsoft Media Foundation AAC MFT hardware/software decoding.
- **Windows Local MP4 Recording (`apps/windows/recording`)**:
  - Zero-transcode Media Foundation Sink Writer muxer (`Mp4Recorder`).
  - Direct muxing of incoming H.264 Annex-B NALUs and AAC audio frames without CPU/GPU overhead.
- **Session Management (`native/session`)**:
  - State machine with heartbeat RTT tracking, ping/pong validation, and rolling stats.

---

## [0.1.0] - 2026-10-13

### Added
- **Protocol v1 Core (`native/protocol`, `apps/android/protocol`)**:
  - Binary framing specification (`MAGIC = 0x43535031` / `CSP1`).
  - Type-safe packet definitions: `HANDSHAKE`, `CONFIG`, `FRAME`, `HEARTBEAT`, `KEEPALIVE`.
  - C++20 standard library codec with strict `-Wall -Wextra -Wconversion -Werror` compliance.
  - Kotlin zero-allocation framing codec with cross-language golden vector test suite.
- **Android Native Capture & Encoding (`apps/android`)**:
  - Hardware accelerated H.264 encoding via `MediaProjection` and `MediaCodec` surface input.
  - Dynamic encoder query engine (`EncoderConfigSelector`) supporting 720p, 1080p, and native device aspect ratios.
  - Bitstream normalization and Annex-B parameter extraction (`H264.kt`).
  - Bounded lock-free SPSC frame queue with intelligent IDR keyframe retention under congestion.
  - Standalone raw H.264 bitstream file recording sink for standalone mobile validation.
- **Windows Receiver Shell (`apps/windows`)**:
  - Direct3D 11 flip-model swapchain renderer (`D3D11Renderer`).
  - Win32 message loop with command line `--smoke-test` support.
