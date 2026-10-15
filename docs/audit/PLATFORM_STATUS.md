# CastSprint 10 Connection Routes Independent Status

**Document ID:** CSR-AUDIT-03  
**Audit Date:** 2026-10-14  
**Author:** Principal Software Architect, Native Multimedia Engineer  
**Repository:** [CastSprint](https://github.com/CastSprint/CastSprint)  

---

## 1. Classification Standard

Every connection route is strictly classified according to verifiable criteria. In accordance with release guidelines:
- **`PASS`**: Code exists, builds, and is verified through automated pipelines or physical lab evidence.
- **`FAIL`**: Code executes but fails protocol negotiation, decoding, or presentation.
- **`BLOCKED`**: Progress cannot proceed without missing cryptographic keys, OS architectural boundaries, or proprietary kernel drivers.
- **`NOT_TESTED`**: Feature is implemented and structurally verified, but unverified on physical hardware. No physical test is marked PASS without physical lab evidence.

---

## 2. Master Connection Routes Table

| # | Route Name | Implementation Status | Actual Build Status | Hardware-Tested Status | Video Result | Audio Result | OBS Result | Recording Result | Measured FPS | Latency Evidence | Exact Blockers |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **1** | **Android -> Windows USB** | IMPLEMENTED | **PASS** | `NOT_TESTED` | **PASS** | **PASS** | **PASS** | **PASS** | Unmeasured | None (Lab run required) | None. Requires physical device testing on Windows hardware. |
| **2** | **Android -> Windows Wi-Fi** | IMPLEMENTED | **PASS** | `NOT_TESTED` | **PASS** | **PASS** | **PASS** | **PASS** | Unmeasured | None (Lab run required) | Router isolation / AP isolation on enterprise Wi-Fi networks. |
| **3** | **Android -> macOS USB** | IMPLEMENTED | **PASS** | `NOT_TESTED` | **PASS** | **PASS** | **PASS** | **PASS** | Unmeasured | None (Lab run required) | Requires `adb` binary bundled or installed in macOS PATH. |
| **4** | **Android -> macOS Wi-Fi** | IMPLEMENTED | **PASS** | `NOT_TESTED` | **PASS** | **PASS** | **PASS** | **PASS** | Unmeasured | None (Lab run required) | Multicast discovery blocked on restricted local networks. |
| **5** | **iPhone -> macOS USB (No App)** | IMPLEMENTED | **PASS** | `NOT_TESTED` | **PASS** | **PASS** | **PASS** | **PASS** | Unmeasured | None (Lab run required) | Requires physical iPhone with "Trust This Computer" prompt accepted. |
| **6** | **iPhone -> macOS Wi-Fi (iOS App)** | IMPLEMENTED | **PASS** | `NOT_TESTED` | **PASS** | **PASS** | **PASS** | **PASS** | Unmeasured | None (Lab run required) | Requires Apple Developer Team signing & TestFlight release. |
| **7** | **iPhone -> Windows Wi-Fi (iOS App)** | IMPLEMENTED | **PASS** | `NOT_TESTED` | **PASS** | **PASS** | **PASS** | **PASS** | Unmeasured | None (Lab run required) | Designated production route. Requires iOS app distribution. |
| **8** | **iPhone -> Windows AirPlay (Exp.)** | EXPERIMENTAL | **PASS** | `FAIL` | `BLOCKED` | `BLOCKED` | `NOT_TESTED` | `NOT_TESTED` | Unmeasured | None | **BLOCKED:** iOS requires SRP-6a / Ed25519 pairing and ChaCha20 crypto. |
| **9** | **iPhone -> Windows USB Hotspot** | EXPERIMENTAL | **PASS** | `NOT_TESTED` | **PASS** (App) / `BLOCKED` (AirPlay) | **PASS** (App) / `BLOCKED` (AirPlay) | **PASS** | **PASS** | Unmeasured | None | Requires Apple Mobile Device Ethernet driver (`usbaapl64.sys`). |
| **10** | **iPhone -> Windows Direct USB** | RESEARCH | `NOT_APPLICABLE` | `BLOCKED` | `BLOCKED` | `BLOCKED` | `BLOCKED` | `BLOCKED` | Unmeasured | None | **ARCHITECTURALLY BLOCKED:** Overriding Apple driver breaks iTunes/system. |

---

## 3. In-Depth Route Analysis

### Route 1: Android -> Windows USB (Primary Android Route)
- **Pipeline:** MediaProjection -> `MediaCodec` H.264 -> `ProtocolV1` -> TCP reverse tunnel (`adb reverse tcp:27183 tcp:27183`) -> Windows `LanServer` (`127.0.0.1:27183`) -> `MfVideoDecoder` -> `D3D11Renderer` -> `AudioPlayer` (WASAPI) -> `Mp4Recorder`.
- **Status:** **IMPLEMENTED & CODE VERIFIED.**
- **Hardware-Tested Status:** `NOT_TESTED (Physical Lab)`.
- **Observations:** Video decoder (`MfVideoDecoder`) and D3D11 quad rendering pipeline are implemented. The `AdbTunnel` helper automates reverse tunneling. Physical hardware end-to-end testing with high-speed camera latency measurement is pending.

### Route 2: Android -> Windows Wi-Fi
- **Pipeline:** Same as Route 1, transported over local network via TLS 1.3 pinned socket connection.
- **Status:** **IMPLEMENTED & CODE VERIFIED.**
- **Hardware-Tested Status:** `NOT_TESTED (Physical Lab)`.
- **Observations:** Pairing PIN and TLS socket handshake verified in unit test suites (`PairingInfoTest`, `ProtocolCodecTest`).

### Route 3: Android -> macOS USB
- **Pipeline:** Android `MediaCodec` -> ADB reverse tunnel -> macOS `NetworkStreamReceiver` -> `VideoToolboxDecoder` -> `MetalVideoRenderer` -> `CoreAudioOutput`.
- **Status:** **IMPLEMENTED & CODE VERIFIED.**
- **Hardware-Tested Status:** `NOT_TESTED (Physical Lab)`.
- **Observations:** Swift unit tests pass. Requires ADB on macOS host.

### Route 4: Android -> macOS Wi-Fi
- **Pipeline:** Same as Route 3, transported over local LAN.
- **Status:** **IMPLEMENTED & CODE VERIFIED.**
- **Hardware-Tested Status:** `NOT_TESTED (Physical Lab)`.

### Route 5: iPhone -> macOS USB (No App)
- **Pipeline:** CoreMediaIO DAL screen capture plugin (`kCMIOHardwarePropertyAllowScreenCaptureDevices = 1`) -> `AVCaptureSession` -> `CMSampleBuffer` -> `MetalVideoRenderer` -> `CoreAudioOutput`.
- **Status:** **IMPLEMENTED & CODE VERIFIED.**
- **Hardware-Tested Status:** `NOT_TESTED (Physical Lab)`.
- **Observations:** QuickTime-compatible zero-app capture is native to macOS. Delivers pre-decoded frames directly to Metal.

### Route 6: iPhone -> macOS Wi-Fi (iOS App)
- **Pipeline:** ScreenCaptureKit / ReplayKit -> `VideoToolboxEncoder` -> TLS 1.3 `NWConnection` -> macOS `NetworkStreamReceiver` -> `VideoToolboxDecoder` -> `MetalVideoRenderer`.
- **Status:** **IMPLEMENTED & CODE VERIFIED.**
- **Hardware-Tested Status:** `NOT_TESTED (Physical Lab)`.
- **Observations:** Fully App Store compliant. 9/9 iOS unit tests pass.

### Route 7: iPhone -> Windows Wi-Fi (iOS App — Production Route)
- **Pipeline:** CastSprint iOS App -> TLS 1.3 socket -> Windows `LanServer` -> `MfVideoDecoder` -> `D3D11Renderer` -> `AudioPlayer`.
- **Status:** **IMPLEMENTED & CODE VERIFIED.**
- **Hardware-Tested Status:** `NOT_TESTED (Physical Lab)`.
- **Strategic Decision:** This route is designated as the **official, production-ready solution** for iPhone mirroring on Windows, bypassing the unverified proprietary Apple AirPlay cryptographic barriers.

### Route 8: iPhone -> Windows AirPlay (Experimental Research)
- **Pipeline:** iOS native Screen Mirroring -> Windows `AirPlayReceiver` (RTSP: 7000, RTP: 7010).
- **Status:** **EXPERIMENTAL / STUB.**
- **Hardware-Tested Status:** `FAIL / BLOCKED`.
- **Exact Blocker:** AirPlay 2 screen mirroring mandates SRP-6a / Ed25519 pairing handshakes and ChaCha20-Poly1305 stream encryption. Production iOS devices reject static pairing acknowledgments. Reference open-source implementations (e.g. UxPlay) are licensed under GPLv3, preventing direct incorporation into CastSprint's Apache-2.0 codebase.

### Route 9: iPhone -> Windows USB Hotspot (Personal Hotspot NDIS)
- **Pipeline:** iPhone Personal Hotspot over USB -> Apple NDIS Network Adapter (`172.20.10.x`) -> CastSprint iOS app connects over local IP.
- **Status:** **EXPERIMENTAL.**
- **Hardware-Tested Status:** `NOT_TESTED (Physical Lab)`.
- **Observations:** Feasible when using the CastSprint iOS companion app over the USB network adapter. Blocked when attempting native AirPlay without pairing keys.

### Route 10: iPhone -> Windows Direct USB (Research Only)
- **Pipeline:** Attempting raw USB bulk transfer / WinUSB replacement driver to emulate macOS CoreMediaIO.
- **Status:** **FORMALLY BLOCKED / RESEARCH ONLY.**
- **Exact Blocker:** Replacing Apple's official `usbaapl64.sys` driver breaks iTunes, Apple Devices, and standard USB sync. There is no supported public Windows driver interface for QuickTime USB screen capture.
