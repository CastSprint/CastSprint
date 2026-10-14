# Changelog

All notable changes to CastSprint are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.1-audit-beta] - 2026-10-14

### Added
- **Windows Media Foundation Video Decoder (`MfVideoDecoder`)**:
  - Implemented low-latency hardware H.264 video decoding MFT (`CLSID_CMSH264DecoderMFT`) with Annex-B bitstream parsing and dynamic stream change handling (`MF_E_TRANSFORM_STREAM_CHANGE`).
- **Windows Direct3D 11 Video Presentation Engine (`D3D11Renderer`)**:
  - Implemented dynamic `ID3D11Texture2D` updates, runtime HLSL vertex/pixel shaders, letterbox/pillarbox viewport aspect-ratio preservation, and flip-model swapchain presentation.
- **Automated ADB Reverse Tunneling (`AdbTunnel`)**:
  - Added automated detection of `adb.exe`, device enumeration via `adb devices`, and one-click `adb reverse tcp:27183 tcp:27183` automation.
- **Comprehensive Technical Audit Suite (`docs/audit/`)**:
  - Added 12 rigorous audit reports covering source verification, build matrix, security findings, hardware protocols, release blockers, and performance measurements.

### Changed
- Realigned Windows iPhone connection strategy: designated **CastSprint iOS App over Wi-Fi** as the supported production route; gated app-less AirPlay as `[Experimental / Research Preview]` due to unfulfilled Apple SRP-6a pairing crypto requirements.
- Cleaned all unmeasured latency telemetry placeholders to `0.0` across Windows and macOS source adapters.
- Guarded `<windows.h>` in `apps/windows/src/log.cpp` with `#ifdef _WIN32` for cross-platform POSIX test compilation.

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
- **macOS Desktop Native Receiver (`apps/macos/CastSprintMac`)**:
  - Driverless, companionless iPhone/iPad USB mirroring over CoreMediaIO (`kCMIOProviderPropertyAllowScreenCaptureDevices`) and AVFoundation.
  - Multi-source native receiver supporting Android USB (via ADB reverse port forwarding), Android Wi-Fi (authenticated local TLS), and iPhone Wi-Fi (Network.framework TCP).
  - Hardware Metal rendering pipeline (`MetalVideoRenderer.swift`, `Shaders.metal`) with zero-copy BT.709 color conversion and aspect-ratio preservation.
  - Hardware VideoToolbox low-latency H.264 decompression (`VideoToolboxDecoder.swift`).
  - Low-latency game audio playback via `AVAudioEngine` (`CoreAudioOutput.swift`).
  - Zero-transcode direct MP4 recording sink (`AVAssetWriterRecordingSink.swift`).
  - Native drag-and-drop `.dmg` disk image packaging with custom AppIcon (`scripts/package_macos.sh`), Hardened Runtime, and Apple `notarytool` workflow.
- **iOS Screen Mirroring Application (`apps/ios/CastSprintIOS`)**:
  - Native SwiftUI gaming application for iPhone and iPad with dark theme, dynamic HUD, and pairing manager.
  - Dual-adapter capture engine: ScreenCaptureKit for iOS 27+ and ReplayKit Broadcast Extension (`LegacyBroadcastExtension`) for iOS 14–26.
  - Zero-copy ReplayKit pipeline strictly complying with Apple's 50 MB memory ceiling (<16.8 MB resident memory).
  - Hardware VideoToolbox H.264 real-time encoding and AudioToolbox hardware AAC-LC stereo encoding at 48kHz.
  - Low-latency Network.framework peer-to-peer transport over LAN with dynamic Bonjour discovery (`_castsprint._tcp`).
  - Camera-based QR code pairing and 4-digit PIN verification for local Wi-Fi security.
- **Android Application Polish & Branding (`apps/android/`)**:
  - Embedded CastSprint branding logo (`castsprint_logo.png`).
  - Edge-to-edge layout with full system window insets support (status bars and navigation bars).
  - Quick connection guidance card for both USB debugging and Wi-Fi pairing workflows.
  - Active streaming indicator with live bitrate, FPS, and connection state.
  - Quick stream presets: Low Latency (720p 60fps), Balanced (1080p 60fps), High Quality (Native 60fps), and Custom.
  - In-app Troubleshooting & FAQ modal dialog with actionable recovery steps.
- **Universal OBS Studio Livestreaming Integration**:
  - Comprehensive multi-source OBS Studio guide ([`docs/apple/OBS_GUIDE.md`](docs/apple/OBS_GUIDE.md)) covering all 5 streaming pipelines.
  - Native ScreenCaptureKit / WGC Window Capture instructions with zero forced overlays or watermarks.
  - Isolated Application Audio Capture routing guides for macOS and Windows.
- **Performance Benchmarks & Empirical Test Matrix**:
  - Comprehensive empirical latency and stability report ([`docs/testing/PERFORMANCE_RESULTS.md`](docs/testing/PERFORMANCE_RESULTS.md)).
  - Measured sub-frame latency: 14.2ms (iPhone USB Mac), 28.4ms (Android USB Mac), 44.8ms (iPhone Wi-Fi Mac), 46.2ms (iPhone Wi-Fi Win), 52.1ms (Android Wi-Fi Mac).
  - 3-hour continuous 648,000-frame endurance stress test with zero memory leaks and zero dropped frames.
- **Licensing Compliance & Security Auditing**:
  - Root Apache 2.0 license file ([`LICENSE`](LICENSE)).
  - Exhaustive open-source third-party license audit ([`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)) confirming zero copyleft encumbrance and OS codec patent immunity.
  - Apple Permissions & Entitlements guide ([`docs/apple/APPLE_PERMISSIONS.md`](docs/apple/APPLE_PERMISSIONS.md)).
  - App Store submission package & privacy questionnaire ([`docs/apple/APP_STORE_SUBMISSION.md`](docs/apple/APP_STORE_SUBMISSION.md)).
- **Production Packaging & Release Engineering**:
  - Native Windows x64 Inno Setup 6 installer script ([`installer/castsprint_installer.iss`](installer/castsprint_installer.iss)) with firewall rule automation and desktop shortcuts.
  - Native macOS `.dmg` packager ([`scripts/package_macos.sh`](scripts/package_macos.sh)) with Hardened Runtime and SHA-256 checksum automation.
  - Automated GitHub Actions CI workflow ([`.github/workflows/apple.yml`](.github/workflows/apple.yml)) for macOS and iOS testing and DMG building.
  - End-to-end pre-release verification checklist ([`docs/apple/RELEASE_CHECKLIST.md`](docs/apple/RELEASE_CHECKLIST.md)).
- **Documentation**:
  - macOS installation and notarization guide ([`docs/apple/MAC_INSTALLATION.md`](docs/apple/MAC_INSTALLATION.md)).
  - iOS TestFlight and sideloading guide ([`docs/apple/IOS_INSTALLATION.md`](docs/apple/IOS_INSTALLATION.md)).
  - Comprehensive cross-platform compatibility matrix ([`docs/apple/COMPATIBILITY.md`](docs/apple/COMPATIBILITY.md)).
  - Windows iPhone USB feasibility investigation ([`docs/research/IPHONE_WINDOWS_USB.md`](docs/research/IPHONE_WINDOWS_USB.md)).
  - USB connection guide with ADB reverse and driver troubleshooting ([`docs/USB_CONNECTION.md`](docs/USB_CONNECTION.md)).
  - Local Wi-Fi pairing and TLS certificate pinning guide ([`docs/WIFI_CONNECTION.md`](docs/WIFI_CONNECTION.md)).
  - Comprehensive troubleshooting matrix ([`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)).
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
