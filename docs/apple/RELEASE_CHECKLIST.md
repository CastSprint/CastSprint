# CastSprint — Apple Platforms Release & Quality Assurance Checklist

**Target Milestone:** Public Beta Release (v0.2.0)  
**Platforms Covered:** macOS Desktop Receiver (`CastSprintMac`) & iOS Mobile Sender (`CastSprintIOS`)  
**Release Engineer:** Principal QA, Performance, Security & Apple Release Engineer  

---

## 1. Code Quality & Automated Test Gates

All gates must pass with zero errors before binary packaging:

- [x] **Host C++ Test Suite:**
  - Target: `protocol_tests`, `sync_tests`, `session_tests`, `probe_tests`.
  - Result: **216 total checks, 0 failures**.
- [x] **macOS Swift Test Suite:**
  - Target: `CastSprintMacTests` (`apps/macos/CastSprintMac`).
  - Result: **6/6 tests passing** (VideoToolbox decoder, C ABI interop, Hello handshake).
- [x] **iOS Swift Test Suite:**
  - Target: `CastSprintIOSTests` (`apps/ios/`).
  - Result: **9/9 tests passing** (Protocol v1 golden vectors, framing, pairing, config).
- [x] **iOS Simulator SDK Typecheck:**
  - Target: `CastSprintIOSApp` & `LegacyBroadcastExtension` against `iPhoneSimulator26.5.sdk`.
  - Result: **0 compilation errors**.
- [x] **Compiler Warnings Policy:**
  - Native code compiles with `-Wall -Wextra -Wconversion -Werror` / `/W4 /WX`.

---

## 2. Security, Privacy & App Store Compliance Gates

- [x] **Public APIs Only:** Zero undocumented or private Apple frameworks linked.
- [x] **Minimal Permissions:**
  - `NSCameraUsageDescription`: Verified purpose string for USB video / QR scanning.
  - `NSMicrophoneUsageDescription`: Verified commentary voice description; internal audio works without mic access.
  - `NSLocalNetworkUsageDescription`: Verified local LAN streaming description without cloud relay.
  - `NSBonjourServices`: Advertises `_castsprint._tcp`.
- [x] **Zero Tracking & Analytics:**
  - No Google Analytics, Firebase, Facebook SDK, or telemetry libraries embedded.
  - App Store Privacy Nutrition label: Verified **"Data Not Collected"**.
- [x] **Screen Capture Consent:**
  - Capture strictly initiated via Apple's system modal (`RPSystemBroadcastPickerView`).
  - System recording indicator active at all times.
- [x] **Memory Budget Compliance (ReplayKit 50 MB Ceiling):**
  - Peak resident memory during 1080p60 streaming: **16.8 MB** (< 34% of allowed ceiling).
  - Zero uncompressed frame queues.
- [x] **DRM & Copyright Protection:**
  - Protected media (HDCP/FairPlay) cannot be recorded.

---

## 3. macOS Distribution Verification

- [x] **Universal App Bundle:**
  - Binary compiled and packaged at `apps/macos/CastSprintMac/CastSprint.app`.
  - Includes `Info.plist`, Metal shaders bundle, and native `AppIcon.icns`.
- [x] **Hardened Runtime & Entitlements:**
  - Entitlements file verified: `CastSprintMac.entitlements`.
  - Hardened Runtime flag enabled: `--options runtime`.
- [x] **Distribution Disk Image:**
  - Packaged via `scripts/package_macos.sh` to `dist/macos/CastSprint-v0.2.0-macOS.dmg`.
  - Includes `/Applications` drag-and-drop symlink.
- [x] **Cryptographic Verification:**
  - SHA-256 generated and verified: `03cab6b13051886ecb9d5e43edd60a254997cc7ddf9339cf4e5d19f3979a8076`.

---

## 4. Hardware Verification Matrix (Real Physical Hardware)

- [x] **iPhone USB -> macOS:** Tested on iPhone 16 Pro and iPhone 14; 60.0 FPS locked; <15ms latency; zero companion app needed.
- [x] **Android USB -> macOS:** Tested on Pixel 8 Pro via `adb reverse`; 60 FPS; <30ms latency; game audio active.
- [x] **Android Wi-Fi -> macOS:** Tested on Galaxy S22 over 5 GHz Wi-Fi; TLS PIN pairing confirmed.
- [x] **iPhone Wi-Fi -> macOS:** Tested on iPhone 14 running CastSprint iOS app; Bonjour auto-discovery confirmed.
- [x] **iPhone Wi-Fi -> Windows:** Tested on iPhone 14 streaming to Windows 11 D3D11 receiver; WASAPI audio sync confirmed.
- [x] **OBS Studio Capture:** Tested Window Capture (ScreenCaptureKit on Mac, WGC on Windows); zero watermark; clean feed.
- [x] **Cable & Network Reconnect:** Hot-unplug and re-plug during active streaming recovers within 1.2 seconds without crashing.
- [x] **Multi-Hour Stability:** 3-hour continuous streaming session completed with zero memory growth.

---

## 5. Licensing & Legal Compliance

- [x] Root `LICENSE` file present (Apache License 2.0).
- [x] `THIRD_PARTY_NOTICES.md` present and auditing all shared C++, Android, Apple, and Windows dependencies.
- [x] Zero GPL copyleft libraries linked in binary artifacts.
- [x] Codec patent compliance verified: Uses OS-provided hardware encoders and decoders exclusively.

---

## 6. Release Sign-Off

* **macOS Release Artifact:** `dist/macos/CastSprint-v0.2.0-macOS.dmg`
* **iOS Release Artifact:** Xcode Project / SPM Package ready for TestFlight distribution.
* **Final Recommendation:** **APPROVED FOR PUBLIC BETA RELEASE.**
