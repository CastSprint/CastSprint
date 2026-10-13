# CastSprint Cross-Platform Compatibility Matrix

This document defines the supported connection methods, hardware requirements, and feature availability across all CastSprint target platforms.

---

## 1. Connection Matrix

| Connection Method | Host Desktop | Mobile Source | Mobile Companion App Needed? | Status | Latency |
|:---|:---:|:---:|:---:|:---:|:---:|
| **iPhone USB** | **macOS 14+** | iOS 14+ | **NO (Zero App)** | **Supported** | **12 – 18 ms** |
| **Android USB** | **macOS 14+** | Android 10+ | Yes (CastSprint Android) | **Supported** | **25 – 35 ms** |
| **iPhone Wi-Fi** | **macOS 14+** | iOS 14+ | Yes (CastSprint iOS) | **Supported** | **40 – 60 ms** |
| **Android Wi-Fi** | **macOS 14+** | Android 10+ | Yes (CastSprint Android) | **Supported** | **45 – 65 ms** |
| **Android USB** | **Windows 10/11** | Android 10+ | Yes (CastSprint Android) | **Supported** | **28 – 38 ms** |
| **Android Wi-Fi** | **Windows 10/11** | Android 10+ | Yes (CastSprint Android) | **Supported** | **45 – 65 ms** |
| **iPhone Wi-Fi** | **Windows 10/11** | iOS 14+ | Yes (CastSprint iOS) | **Supported** | **40 – 60 ms** |
| **iPhone USB** | **Windows 10/11** | iOS 14+ | — | **Planned / Under Study** | N/A |

---

## 2. Feature Gating & Capability Definitions

To prevent user confusion and maintain high reliability, CastSprint adheres to strict **Feature Gating**:
- **Never expose an unimplemented feature as functional.**
- Desktop interfaces dynamically query `PlatformCapabilities` to render only verified connection methods.

### Capability Flags in Code
```swift
struct PlatformCapabilities {
    let supportsIPhoneUsb: Bool       // true on macOS, false on Windows
    let supportsAndroidUsb: Bool      // true on macOS (via adb) and Windows
    let supportsIPhoneWifi: Bool      // true on both (via CSP1 protocol)
    let supportsAndroidWifi: Bool     // true on both (via CSP1 protocol)
    let supportsMetalRendering: Bool  // true on macOS
    let supportsD3D11Rendering: Bool  // true on Windows
    let supportsCoreAudio: Bool       // true on macOS
    let supportsWasapi: Bool          // true on Windows
}
```

### Windows iPhone USB Evaluation Status
- On Windows, Apple does not provide a native CoreMediaIO subsystem.
- Apple's Windows drivers (via iTunes / Apple Devices app) expose MTP/PTP storage and network tethering, but do not provide raw AV capture endpoints without undocumented usbmuxd multiplexing.
- **Decision**: In the Windows UI, "iPhone USB" is explicitly labeled as **"Under Feasibility Evaluation"** and disabled until a robust, driver-compliant implementation is validated. Users on Windows with iPhones are directed to **iPhone Wi-Fi Mode**.

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
