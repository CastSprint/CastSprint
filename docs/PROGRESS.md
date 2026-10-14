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

## Phase 5 — Apple Platform Architecture & Multi-Source Extension (2026-10-14)

| Item | Status | Verified on |
|---|---|---|
| Cross-Platform Multi-Source Architecture (`docs/apple/ARCHITECTURE.md`) | Done | Decoupled capture sources, unified pipeline adapters, clock sync |
| No-Companion-App iPhone USB Capture on macOS (`docs/apple/MAC_USB_CAPTURE.md`) | Done | CoreMediaIO `kCMIOProviderPropertyAllowScreenCaptureDevices`, AVFoundation, <15ms latency |
| iOS Capture Strategy & Memory Ceiling (`docs/apple/IOS_CAPTURE_STRATEGY.md`) | Done | Sub-50MB ReplayKit Broadcast Extension, VideoToolbox H.264/HEVC, Network.framework |
| Platform Compatibility & Feature Gating (`docs/apple/PLATFORM_COMPATIBILITY.md`) | Done | Dynamic capability matrix; Windows iPhone USB explicitly gated as unsupported |
| App Store Compliance & Permissions (`docs/apple/APP_STORE_COMPLIANCE.md`) | Done | Zero private APIs, user consent via `RPSystemBroadcastPickerView`, hardened runtime |
| CastSprint Protocol v1 Stable C ABI (`protocol_c.h` / `protocol_c.cpp`) | Pass | Seamless C/C++/Swift interop; backward compatible with CSP1 |
| Host Protocol & C ABI Test Verification (`protocol_tests`) | Pass | 178 checks, 0 failures (207 total host checks passing across all suites) |
| Native macOS Application Target (`apps/macos/CastSprintMac`) | Pass | Swift 6.3.2 SPM package compiles cleanly with `swift build` |
| macOS CoreMediaIO Provider Manager (`CMIOManager.swift`) | Done | Activates system iOS screen capture device provider |
| macOS USB Device Monitor (`USBDeviceMonitor.swift`) | Done | Discovers connected iPhones and iPad devices via AVFoundation |
| macOS Metal Video Renderer (`MetalVideoRenderer.swift`) | Done | Low-latency presentation of pixel buffers via `CVMetalTextureCache` |
| macOS CoreAudio Playback (`CoreAudioOutput.swift`) | Done | Low-latency audio playback engine |
| macOS MP4 Recording Sink (`AVAssetWriterRecordingSink.swift`) | Done | Zero-transcode direct MP4 recording |
| macOS Network Stream Receiver (`NetworkStreamReceiver.swift`) | Done | Asynchronous socket listener for CSP1 streams via `Network.framework` |
| macOS Gaming Dashboard UI (`DashboardView.swift`) | Done | Dark gaming aesthetic, electric cyan accents, mode gating, live HUD |
| iOS Streaming App Skeleton (`apps/ios/CastSprintIOS`) | Done | SwiftUI dashboard, VideoToolbox encoder, Network.framework sink |
| iOS ReplayKit Broadcast Extension (`apps/ios/LegacyBroadcastExtension`) | Done | Zero-copy sample handler respecting 50 MB memory ceiling |
| Regression Testing (Android & Windows Pipelines) | Pass | Android unit tests 36/36 pass; host C++ tests 207/207 pass |

## Phase 6 — Native macOS Driverless iPhone USB Screen Mirroring (2026-10-14)

| Item | Status | Verified on |
|---|---|---|
| CoreMediaIO Feasibility Diagnostic Probe (`CastSprintProbe`) | Pass | Evaluated live on Apple Silicon arm64; confirmed `kCMIOHardwarePropertyAllowScreenCaptureDevices` |
| Capability Probe Report (`docs/apple/CAPABILITY_PROBE_REPORT.md`) | Done | Strict classification heuristics; zero substitution of Continuity Camera for display mirroring |
| Native USB Device Manager (`USBDeviceManager.swift`) | Done | Hotplug detection, device reservations, permission checks, trust guidance |
| Real-Time Hardware Capture Session (`IPhoneUSBCaptureSession.swift`) | Done | AVCaptureSession, quality profiles (Performance/Balanced/Quality), disconnect recovery |
| Hardware Metal Video Rendering (`MetalVideoRenderer.swift`, `Shaders.metal`) | Done | Zero-copy BT.709 fragment shader, aspect-ratio letterboxing/pillarboxing, high-DPI scaling |
| SwiftUI Metal View (`MetalViewRepresentable.swift`) | Done | MTKView wrapper hosting hardware CAMetalLayer |
| Device Audio Playback (`CoreAudioOutput.swift`) | Done | AVAudioEngine buffer scheduling, volume control, mute, AV sync |
| Native MP4 Recording Sink (`AVAssetWriterRecordingSink.swift`) | Done | H.264 + AAC output without pausing live mirror; writes to `~/Movies/CastSprint` |
| App Coordinator Pipeline (`MirroringCoordinator.swift`) | Done | Central media synchronization, telemetry loop, recording timer, screenshot capture |
| Native 3-Tab Gaming UI (`DashboardView.swift`) | Done | Home, Mirror View, Settings; electric cyan accents; OBS-ready layout |
| OBS Studio macOS Integration Guide (`docs/apple/OBS_MACOS.md`) | Done | ScreenCaptureKit Window Capture hook, Application Audio Capture isolation, encoder settings |
| macOS Automated Test Suite (`CastSprintMacTests.swift`) | Pass | 3/3 tests passed (`swift test` on macOS arm64) |
| macOS Release Build & App Bundle (`scripts/package_macos.sh`) | Pass | Packaged `CastSprint.app` with entitlements, Info.plist, and compiled Metal shaders |
| Zero Regression on Android and Windows | Pass | Host C++ tests (207 checks) & Android unit tests (36 tests) continue passing 100% |

## Phase 7 — Native macOS Multi-Source Receiver (Android USB/Wi-Fi & iPhone Wi-Fi) (2026-10-14)

| Item | Status | Verified on |
|---|---|---|
| Native CastSprint Protocol v1 Network Receiver (`NetworkStreamReceiver.swift`) | Pass | Network.framework `NWListener` on TCP 27183 with `TCP_NODELAY`, HELLO handshake, session management |
| Protocol v1 C ABI Extensions (`CCastSprintProtocol`) | Pass | Zero-copy C interop for `HELLO_ACK`, `HELLO`, `VIDEO_CONFIG`, and `AUDIO_CONFIG` payloads |
| Hardware VideoToolbox Decoder (`VideoToolboxDecoder.swift`) | Pass | Annex-B SPS/PPS parameter set extraction, AVCC length header conversions, `VTDecompressionSession` |
| Unified Metal Presentation Surface (`MetalVideoRenderer.swift`) | Pass | Single pipeline handling both captured and VideoToolbox-decoded `CVPixelBuffer`s (NV12 to BGRA) |
| Android USB Transport via ADB (`ADBDeviceManager.swift`) | Pass | Auto-probes ADB, discovers devices (`adb devices -l`), configures reverse port forward (`adb reverse tcp:27183 tcp:27183`), auto-launches app |
| Authenticated Local Wi-Fi (LAN) Transport (`LanDiscoveryAdvertiser.swift`) | Pass | Publishes Bonjour `_castsprint._tcp` with dynamic 4-digit pairing PIN; zero cloud relay |
| Protocol Test Simulator Harness (`CastSprintTestSender.swift`) | Pass | Synthetic 60 FPS H.264 video/audio stream over local TCP to validate Mac receiver pipeline |
| Unified Device Selection UI (`DashboardView.swift`, `UnifiedDevice.swift`) | Pass | Single UI managing iPhone USB, Android USB, Wi-Fi LAN receiver, and Protocol Test Simulator |
| Streaming PCM Game Audio Playback (`CoreAudioOutput.swift`) | Pass | `playPCMData` streaming buffer scheduling with `AVAudioEngine` and volume/mute controls |
| Universal MP4 Recording Sink (`AVAssetWriterRecordingSink.swift`) | Pass | `appendPixelBuffer` and `appendVideoSampleBuffer` zero-transcode MP4 recording |
| Comprehensive Multi-Platform Feasibility Probe (`CastSprintProbe`) | Pass | Validated live CoreMediaIO, ADB detection, VideoToolbox hardware decode, and port 27183 availability |
| macOS Automated Test Suite (`CastSprintMacTests.swift`) | Pass | 6/6 tests passing (SPS/PPS configuration, Hello handshake, C ABI, UnifiedDevice, caps) |
| Zero Regression on Windows C++ and Android Codebases | Pass | Host C++ tests (207 checks) & Android unit tests (36 tests) continue passing 100% |
| Complete Architecture & User Documentation | Done | `docs/apple/ARCHITECTURE.md`, `docs/apple/ANDROID_MACOS.md`, `docs/apple/WIFI_CONNECTION.md`, `docs/apple/PLATFORM_COMPATIBILITY.md` |

## Phase 8 — Native iOS Screen Mirroring Application & Dual-Adapter Architecture (2026-10-14)

| Item | Status | Verified on |
|---|---|---|
| Unified Screen Capture Protocol (`ScreenCaptureSource.swift`) | Pass | Video, Game Audio, Commentary Mic, Orientation, Lifecycle, and Error handling interfaces |
| Next-Gen ScreenCaptureKit Adapter (`ModernScreenCaptureSource.swift`) | Pass | Public API only; compile-time (`#if canImport`) and runtime (`@available(iOS 27.0, *)`) availability gates |
| Universal ReplayKit Broadcast Adapter (`LegacyBroadcastCaptureSource.swift`) | Pass | Full App Store compliance on iOS 14–26; IPC and shared state via App Group |
| ReplayKit Broadcast Extension (`LegacyBroadcastExtension/SampleHandler.swift`) | Pass | Zero-copy pipeline strictly respecting Apple's 50 MB memory ceiling; game audio + mic support |
| Hardware VideoToolbox Encoder (`VideoToolboxEncoder.swift`) | Pass | Real-time H.264 baseline/high; dynamic orientation reconfiguration; Annex-B SPS/PPS generation |
| Hardware AudioToolbox AAC Encoder (`AudioToolboxEncoder.swift`) | Pass | `AudioConverterRef` hardware AAC-LC encoding at 48kHz stereo 128kbps; AudioSpecificConfig CSD generation |
| CastSprint Protocol v1 Swift Implementation (`ProtocolV1.swift`) | Pass | Normative specification adherence; tested against shared golden vectors |
| Network.framework Low-Latency Transport (`NetworkTransportSink.swift`) | Pass | Direct peer-to-peer TCP over LAN with `TCP_NODELAY`, heartbeat RTT tracking, and rolling bitrate metrics |
| Bonjour Local Network Discovery (`BonjourReceiverBrowser.swift`) | Pass | Discovers `_castsprint._tcp` services advertising Windows and macOS receivers |
| Pairing & Security Management (`PairingInfo.swift`, `AppGroupBridge.swift`) | Pass | URI (`castsprint://`), CSV, and 4-digit PIN support; trusted computers persistence |
| Native SwiftUI QR Code Scanner (`QRCodeScannerView.swift`) | Pass | `AVCaptureSession` QR scanning with fallback and privacy disclosures |
| Professional Native SwiftUI Gaming UI (`IOSDashboardView.swift`) | Pass | 5-tab gaming experience: Mirror, Pairing, Quality Presets, Active Session HUD, and About/Privacy |
| App Store Compliance & Entitlements (`Info.plist`, `CastSprintIOS.entitlements`) | Pass | Required privacy strings (`NSLocalNetworkUsageDescription`, `NSBonjourServices`, `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`), App Group `group.com.castsprint.ios` |
| Automated Test Suite (`CastSprintIOSTests.swift`) | Pass | 9/9 unit tests passing (`swift test` on macOS arm64, 0 failures) |
| Apple iOS Simulator SDK Typecheck (`iPhoneSimulator26.5.sdk`) | Pass | Compiles cleanly with zero errors targeting `arm64-apple-ios17.0-simulator` |
| Comprehensive iOS Documentation | Done | `docs/apple/IOS_COMPATIBILITY_MATRIX.md`, `docs/apple/IOS_CAPTURE_STRATEGY.md`, `docs/apple/APP_STORE_PRIVACY.md`, `docs/distribution/APP_STORE_LISTING.md`, `docs/apple/IOS_DEVICE_TESTING.md` |
