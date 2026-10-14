# CastSprint Cross-Platform Compatibility Matrix

This document defines the supported connection methods, hardware requirements, and feature availability across all CastSprint target platforms.

---

## 1. Connection Matrix

| Connection Method | Host Desktop | Mobile Source | Mobile Companion App Needed? | Status | Latency |
|:---|:---:|:---:|:---:|:---:|:---:|
| **iPhone USB** | **macOS 14+** | iOS 14+ | **NO (Zero App)** | **Verified Operational** | **12 – 18 ms** |
| **Android USB** | **macOS 14+** | Android 10+ | Yes (CastSprint Android) | **Verified Operational (ADB)** | **25 – 35 ms** |
| **Android Wi-Fi** | **macOS 14+** | Android 10+ | Yes (CastSprint Android) | **Verified Operational (LAN)** | **45 – 65 ms** |
| **iPhone Wi-Fi** | **macOS 14+** | iOS 14+ | Yes (CastSprint iOS) | **Receiver Ready (Verified via Simulator)** | **40 – 60 ms** |
| **Android USB** | **Windows 10/11** | Android 10+ | Yes (CastSprint Android) | **Verified Operational** | **28 – 38 ms** |
| **Android Wi-Fi** | **Windows 10/11** | Android 10+ | Yes (CastSprint Android) | **Verified Operational** | **45 – 65 ms** |
| **iPhone AirPlay Wi-Fi** | **Windows 10/11** | iOS 14+ | **NO (Zero App)** | **Native Prototype Operational** | **45 – 65 ms** |
| **iPhone AirPlay USB (Hotspot)** | **Windows 10/11** | iOS 14+ | **NO (Zero App)** | **Prototype Working (AirPlay over USB NDIS)** | **22 – 32 ms** |
| **iPhone Wi-Fi (CastSprint App)** | **Windows 10/11** | iOS 14+ | Yes (CastSprint iOS) | **Receiver Protocol Ready** | **40 – 60 ms** |
| **iPhone USB (Direct QuickTime)** | **Windows 10/11** | iOS 14+ | **NO (Zero App)** | **Blocked / Not Recommended (Driver Conflict)** | N/A |

---

## 2. Feature Gating & Capability Definitions

To prevent user confusion and maintain high reliability, CastSprint adheres to strict **Feature Gating**:
- **Never expose an unimplemented feature as functional.**
- Desktop interfaces dynamically query `PlatformCapabilities` to render only verified connection methods.

### Capability Flags in Code
```swift
struct PlatformCapabilities {
    let supportsIPhoneUsb: Bool       // true on macOS, false on Windows (direct CoreMediaIO)
    let supportsAndroidUsb: Bool      // true on macOS (via adb) and Windows
    let supportsIPhoneWifi: Bool      // true on both (via CSP1 protocol)
    let supportsAndroidWifi: Bool     // true on both (via CSP1 protocol)
    let supportsAirPlayReceiver: Bool // true on Windows (native C++20 AirPlay engine)
    let supportsMetalRendering: Bool  // true on macOS
    let supportsD3D11Rendering: Bool  // true on Windows
    let supportsCoreAudio: Bool       // true on macOS
    let supportsWasapi: Bool          // true on Windows
}
```

### Windows iPhone Mirroring Evaluation Status
- Comprehensive systems re-evaluation completed (see [`docs/research/IPHONE_WINDOWS_USB.md`](../research/IPHONE_WINDOWS_USB.md) and [`docs/research/WINDOWS_AIRPLAY_FEASIBILITY.md`](../research/WINDOWS_AIRPLAY_FEASIBILITY.md)).
- **Native AirPlay Receiver (Wi-Fi & USB Hotspot):** **PROTOTYPE OPERATIONAL.** Isolated clean-room C++20 RTSP state machine and depacketizer with Direct3D 11 video presentation and WASAPI audio playback. Zero copyleft GPL code; zero FairPlay DRM circumvention.
- **AirPlay over USB Personal Hotspot (NDIS):** **PROTOTYPE WORKING (Conditional Go).** Apple's official `Apple Mobile Device Ethernet` NDIS driver enables wired TCP/IP over the USB cable without third-party driver modifications. Measured latency: ~24.6 ms, 60 FPS, full game audio, zero app required.
- **Direct Raw USB Endpoints (Approach C):** BLOCKED / NOT RECOMMENDED. Replacing Apple's signed driver (`usbaapl64.sys`) with WinUSB breaks iTunes, Apple Devices, and iOS synchronization.
- **Production Baseline:** The primary production path remains the **CastSprint iOS App over local Wi-Fi** (sub-45ms dedicated gaming stream). Plug-and-play USB mirroring without Personal Hotspot remains unique to the **CastSprint macOS receiver** via Apple's native `CoreMediaIO` provider.

---

## 3. Platform System Requirements

### macOS Desktop (Host Receiver)
- **Operating System**: macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia).
- **Architecture**: Apple Silicon (M1/M2/M3/M4) recommended; Intel Core i5/i7 (x86_64) supported.
- **Permissions Required**: Camera permission (required by macOS to access USB video capture devices).

### Windows Desktop (Host Receiver)
- **Operating System**: Windows 10 (version 1903+) or Windows 11 64-bit.
- **Hardware**: Direct3D 11 compatible GPU (Intel HD 5000+, NVIDIA GTX 900+, AMD Radeon RX 400+).
- **Prerequisites**: Media Feature Pack enabled on Windows N editions.

### Android Mobile (Capture Sender)
- **Operating System**: Android 10 (API 29) through Android 15/16 (API 36).
- **Hardware**: Hardware H.264 video encoder (`c2.android.avc.encoder` or vendor hardware).
- **Internal Audio**: Android 10+ required for `AudioPlaybackCapture`.

### iOS Mobile (Capture Sender)
- **Operating System**: iOS 14.0+ through iOS 18+.
- **Hardware**: iPhone 8 / iPhone X or newer.
- **USB Mode to Mac**: Any Lightning or USB-C iPhone; no companion app required.
- **Wi-Fi Mode**: CastSprint iOS application with Broadcast Extension.
