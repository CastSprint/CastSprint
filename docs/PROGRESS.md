# Progress

## Phase 1 — Foundation (2026-10-13)

| Item | Status | Verified on |
|---|---|---|
| Protocol v1 spec (`docs/architecture/PROTOCOL.md`) | Done | — |
| C++20 protocol codec (`native/protocol`) | Done | macOS arm64, AppleClang 21, `-Wall -Wextra -Wconversion -Werror` |
| Protocol tests (round-trip, invalid packets, versions, golden vector) | Pass | macOS (CTest); also run under ASan/UBSan |
| Kotlin protocol subset + JVM tests (shared golden vector) | Pass | `./gradlew testDebugUnitTest` |
| Android app (`com.castsprint.android`) assemble + lint | Pass | AGP 8.13.2, Gradle 8.13, JDK 17 |
| Windows Win32 + D3D11 receiver shell | Done | Visual Studio 2022 C++20 / MSVC (CI `windows.yml`) |
| Windows `--smoke-test` startup test | Done | Clean headless verification mode |
| GitHub Actions workflows | Done | `windows.yml`, `android.yml`, `host.yml` |
| License | Done | Apache 2.0 (see `docs/development/LICENSING.md`) |

## Phase 2 — Android Capture & Hardware Encoding (2026-10-14)

| Item | Status | Verified on |
|---|---|---|
| MediaProjection + FGS lifecycle (`ScreenCaptureService`) | Done | Android 10+ / Android 14+ FGS compliance, tested on API 36.1 |
| Zero-copy VirtualDisplay -> Surface -> MediaCodec pipeline | Done | Hardware/software AVC encoder, surface input |
| Dynamic capability query & fallback (`EncoderConfigSelector`) | Done | 6 unit tests; verified on emulator (`c2.android.avc.encoder`) |
| Bitstream normalization & Annex-B framing (`H264.kt`) | Done | 6 unit tests; SPS/PPS extraction, IDR detection |
| SPSC bounded buffer queue & backpressure (`FrameQueue`) | Done | 3 unit tests; frame dropping under load, IDR preservation |
| Protocol v1 transport sink (`TcpTransportSink`) | Done | Handshake, config, frame packets, heartbeat |
| Standalone H.264 file sink (`FileTransportSink`) | Done | Zero PC dependency test mode; valid Annex-B bitstream output |
| Native UI with branding, controls, and live stats | Done | Dark theme, resolution/FPS/bitrate/mode selectors, live stats |
| End-to-end device capture verification | Pass | Verified with `ffprobe` (864x1920, Constrained Baseline, valid NALs) |
| Unit test suite (24 tests) & Android lint | Pass | `./gradlew testDebugUnitTest lintDebug` (0 warnings/errors) |

## Phase 3 — Secure Wi-Fi, Game Audio, AV Sync & Local MP4 Recording (2026-10-14)

| Item | Status | Verified on |
|---|---|---|
| Protocol v1 Audio messages (`AUDIO_CONFIG`, `AUDIO_FRAME`) | Done | Verified in C++ (`protocol_tests`) and Kotlin (`ProtocolCodecTest`) |
| Android AudioPlaybackCapture engine (`AudioCaptureEngine`) | Done | Android 10+ API; 48kHz PCM -> MediaCodec AAC-LC stereo; no mic access |
| Bounded audio frame queue (`AudioFrameQueue`) | Done | 3 unit tests passing; oldest-frame eviction under backpressure |
| Secure Wi-Fi TLS pinning (`TlsPinningSocketFactory`) | Done | SHA-256 certificate fingerprint pinning; zero trust-all fallbacks |
| LAN mDNS receiver discovery (`LanDiscovery`) | Done | `NsdManager` discovering `_castsprint._tcp` with fingerprint TXT record |
| Wi-Fi pairing model & dialog (`PairingInfo`, UI) | Done | CSV/URI parsing, dialog with PIN and fingerprint input, SharedPreferences |
| Gaming stream presets | Done | Low Latency (720p 60fps 8M), Balanced (1080p 60fps 12M), High Quality (Native 60fps 20M) |
| C++20 AV Synchronizer (`AvSynchronizer`) | Pass | 10 unit tests passing; monotonic PTS alignment, drift tracking, user offset |
| C++20 Session Manager (`SessionManager`) | Pass | 19 unit tests passing; PIN auth, heartbeat RTT tracking, rolling stats |
| Windows Audio Engine (`AudioPlayer`) | Done | Media Foundation AAC MFT decoder + WASAPI shared mode + IMMNotificationClient |
| Windows Native MP4 Recorder (`Mp4Recorder`) | Done | Media Foundation Sink Writer; passthrough H.264 & AAC muxing; clean finalization |
| Windows Secure LAN Server (`LanServer`) | Done | SChannel TLS listener; self-signed cert generation; SHA-256 fingerprint; PIN auth |
| Windows Receiver UI Integration (`MainWindow`) | Done | Hotkeys (R: Record, M: Mute, Up/Down: Volume, [/]: Offset, 1-3: Presets), Titlebar stats |
| Host test suites (182 tests) | Pass | `protocol_tests`, `sync_tests`, `session_tests` (0 failures) |
| Android unit test suite (36 tests) | Pass | `./gradlew testDebugUnitTest` (0 warnings/errors) |

## Phase 4 — Public Beta Polish & Release Readiness (2026-10-14)

| Item | Status | Verified on |
|---|---|---|
| Windows 6-Screen Native Gaming UI (`MainWindow`) | Done | Win32 / GDI double-buffered + Direct3D 11 rendering surface |
| Screen 1: Home / Connection Mode Tabs & Pairing Display | Done | USB and Wi-Fi tab selectors, dynamic PIN display, quick instructions |
| Screen 2: Gaming View with Clean Overlays & F11 Fullscreen | Done | Borderless fullscreen toggle, aspect-ratio preservation, D3D11 surface |
| Screen 3: Stream Settings Controls | Done | Preset selectors, custom resolution, FPS, bitrate toggles |
| Screen 4: Recording / Replay Manager | Done | Direct MP4 passthrough recording, timer display, instant hotkey toggle (`R`) |
| Screen 5: Performance & Diagnostics HUD | Done | Real-time FPS, latency, jitter, bitrate graph, dropped frames, AV sync offset |
| Screen 6: Settings & Shortcuts Panel | Done | Audio device routing, autoconnect options, hotkey reference table |
| Windows Resource & App Icon | Done | Version resource metadata (`version.rc`) and CastSprint icon (`app.ico`) |
| Android CastSprint Branding & Edge-to-Edge Layout | Done | Embedded logo, system window insets padding for status and navigation bars |
| Android Quick Connection Guidance Card | Done | Step-by-step guidance cards for USB (`adb reverse`) and Wi-Fi pairing |
| Android Troubleshooting & FAQ Dialog | Done | In-app modal with actionable recovery solutions |
| OBS Studio Livestreaming Integration Guide (`docs/OBS_GUIDE.md`) | Done | WGC Window Capture, Game Capture, Application Audio, low-latency encoder setup |
| Latency Profiling & Measurement Methodology (`docs/PERFORMANCE.md`) | Done | High-speed camera methodology, latency budget breakdown, backpressure drops |
| USB Connection & Driver Guide (`docs/USB_CONNECTION.md`) | Done | Developer options, OEM drivers, ADB reverse port forwarding, diagnostics |
| Wi-Fi Connection & TLS Guide (`docs/WIFI_CONNECTION.md`) | Done | Local LAN discovery, PIN auth, SChannel TLS pinning, Windows firewall configuration |
| Comprehensive Troubleshooting Matrix (`docs/TROUBLESHOOTING.md`) | Done | Matrix covering video, audio, network, thermal throttling, recording, and OBS |
| Privacy Policy & Free Forever Pledge (`docs/PRIVACY.md`) | Done | Zero cloud, zero telemetry, no mic access, local TLS, permanent free pledge |
| Windows Inno Setup 6 Installer (`installer/castsprint_installer.iss`) | Done | Native x64 installer script with firewall rules, icon, uninstaller |
| Google Play Store Listing Specification (`docs/distribution/`) | Done | App store copy, feature highlights, graphic requirements, permissions |
| Pre-Release Verification Checklist (`docs/RELEASE_CHECKLIST.md`) | Done | Complete pre-release smoke, test, and hardware matrix checklist |
| Release Notes & Documentation Overhaul (`CHANGELOG.md`, `README.md`) | Done | v0.2.0-beta release notes, comprehensive quick start, and architecture map |
