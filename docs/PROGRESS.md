# Progress

## Phase 1 — Foundation (2026-10-13)

| Item | Status | Verified on |
|---|---|---|
| Protocol v1 spec (`docs/architecture/PROTOCOL.md`) | Done | — |
| C++20 protocol codec (`native/protocol`) | Done | macOS arm64, AppleClang 21, `-Wall -Wextra -Wconversion -Werror` |
| Protocol tests (round-trip, invalid packets, versions, golden vector) | Pass | macOS (CTest); also run under ASan/UBSan |
| Kotlin protocol subset + JVM tests (shared golden vector) | Pass | `./gradlew testDebugUnitTest` |
| Android app (`com.castsprint.android`) assemble + lint | Pass | AGP 8.13.2, Gradle 8.13, JDK 17 |
| Windows Win32 + D3D11 receiver shell | Written, **not compiled locally** | Pending: Windows/MSVC (CI `windows.yml`) |
| Windows `--smoke-test` startup test | Written, **not run locally** | Pending: Windows |
| GitHub Actions workflows | Written, not yet run | Needs push |
| License | **Decision pending** | see `docs/development/LICENSING.md` |

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
