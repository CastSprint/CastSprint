# CastSprint macOS — Comprehensive Connection Matrix

## Executive Overview
CastSprint for macOS provides a unified multi-platform mirroring engine capable of receiving low-latency gameplay streams from both **iOS (iPhone / iPad)** and **Android** devices over USB and local network transports.

This matrix documents the verification status, architecture, protocols, codecs, and operational characteristics of all 10 supported and evaluated connection routes.

---

## Master Connection Matrix

| Connection Mode | Target Platform | Transport | Protocol / Mechanism | Video Pipeline | Audio Pipeline | Mobile App Required | Latency Target | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **iPhone USB Screen Capture** | iOS 14+ | Direct USB Cable (USB-C / Lightning) | CoreMediaIO `AllowScreenCaptureDevices` + AVFoundation | Uncompressed NV12 Metal zero-copy | CoreAudio PCM | **NO** (Zero App) | < 15 ms | **VERIFIED_WORKING** |
| **iPhone Wi-Fi (CastSprint iOS)** | iOS 15+ | Local Wi-Fi (Same Subnet) | Bonjour mDNS + TCP 27183 + CSP Protocol | VideoToolbox H.264 Hardware Decode | CoreAudio PCM / AAC | **YES** (CastSprint iOS) | 20–35 ms | **VERIFIED_WORKING** |
| **Apple AirPlay (System Mode)** | iOS / iPadOS | Local Wi-Fi / Peer-to-Peer AirPlay | Apple Native AirPlay 2 Protocol | System AirPlay Receiver Surface | macOS System Output | **NO** (Zero App) | 80–150 ms | **VERIFIED_WORKING** |
| **iPhone USB Network Streaming** | iOS 15+ | USB Personal Hotspot (NCM/CDC) | TCP over Link-Local IP (172.20.10.x) | VideoToolbox H.264 Hardware Decode | CoreAudio PCM | **YES** (CastSprint iOS) | 15–25 ms | **VERIFIED_WORKING** |
| **Android USB (ADB Reverse)** | Android 8.0+ | USB Cable (USB Debugging) | `adb reverse tcp:27183 tcp:27183` + CSP Protocol | Hardware H.264 VideoToolbox Decode | AudioPlaybackCapture PCM | **YES** (CastSprint Android) | < 25 ms | **VERIFIED_WORKING** |
| **Android Secure Wi-Fi** | Android 8.0+ | Local Wi-Fi (Same Subnet) | Bonjour mDNS + PIN Verification + TCP 27183 | Hardware H.264 VideoToolbox Decode | AudioPlaybackCapture PCM | **YES** (CastSprint Android) | 25–40 ms | **VERIFIED_WORKING** |
| **Android Wi-Fi Hotspot LAN** | Android 8.0+ | Direct Phone Wi-Fi Hotspot | TCP over Hotspot Gateway (192.168.43.x) | Hardware H.264 VideoToolbox Decode | AudioPlaybackCapture PCM | **YES** (CastSprint Android) | 20–35 ms | **VERIFIED_WORKING** |
| **Android Wireless ADB** | Android 11+ | Wi-Fi / Local Network | `adb pair` + `adb connect` + Reverse Proxy | Hardware H.264 VideoToolbox Decode | AudioPlaybackCapture PCM | **YES** (CastSprint Android) | 25–40 ms | **VERIFIED_WORKING** |
| **USB Network Tethering** | Android / iOS | USB Ethernet (CDC-NCM / RNDIS) | Direct IP Socket over USB NIC | Hardware H.264 VideoToolbox Decode | CoreAudio PCM | **YES** (Mobile App) | 15–25 ms | **EXPERIMENTAL** |
| **Bluetooth Discovery Assistant** | Android / iOS | Bluetooth Low Energy (BLE) | CoreBluetooth Peripheral Scanning | N/A (Discovery Only) | N/A | Optional | N/A | **VERIFIED_WORKING** |

---

## Detailed Classification Definitions

- **VERIFIED_WORKING:** Fully implemented in source code, compiling in release builds, validated through automated unit/integration tests and real execution on Apple Silicon hardware.
- **IMPLEMENTED_UNTESTED:** Code path complete and compiles, pending specific physical peripheral hardware attach.
- **PARTIALLY_IMPLEMENTED:** Core transport active, secondary enhancements (e.g., automated bitrate laddering) in development.
- **EXPERIMENTAL:** Functional on supported hardware (e.g. CDC-NCM USB tethering) but depends on external driver or OEM configuration on macOS.
- **BLOCKED:** Inherently constrained by operating system security policies, DRM, or hardware bus limitations (e.g., Bluetooth for raw video).

---

## Architectural Route Breakdown

### 1. iPhone USB Screen Capture (Zero Mobile App)
- **Engine:** [`IPhoneUSBCaptureSession.swift`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/Capture/IPhoneUSBCaptureSession.swift) & [`USBDeviceManager.swift`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/Devices/USBDeviceManager.swift)
- **Subsystem:** Activates CoreMediaIO property `kCMIOHardwarePropertyAllowScreenCaptureDevices`.
- **Classification:** Strict separation between Continuity Camera (webcam) and dedicated USB Screen Capture. If an iPhone is detected via Continuity Camera without cable trust, the UI provides unambiguous guidance.

### 2. iPhone Wi-Fi (CastSprint iOS)
- **Engine:** [`apps/ios/CastSprintIOS`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/ios/CastSprintIOS) + [`NetworkStreamReceiver.swift`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/Streaming/NetworkStreamReceiver.swift)
- **Subsystem:** Native ReplayKit / ScreenCaptureKit broadcast extension on iOS encodes video via VideoToolbox into H.264 NALUs and transmits over TCP port 27183. Mac receives and renders via Metal.

### 3. Apple AirPlay (System Mode)
- **Engine:** [`AirPlaySystemIntegration`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/Capture/SourceAdapters.swift)
- **Subsystem:** Native macOS AirPlay Receiver integration via System Settings. Suitable for presentations and zero-setup demonstration.

### 4. Android USB (ADB Reverse)
- **Engine:** [`ADBDeviceManager.swift`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/Devices/ADBDeviceManager.swift)
- **Subsystem:** Event-driven ADB device tracking over persistent TCP socket (`0012host:track-devices` on port 5037). Reverse port forwarding `tcp:27183 -> tcp:27183` allows Android phone to connect to `127.0.0.1:27183`.

### 5. Android Secure Wi-Fi
- **Engine:** [`LanDiscoveryAdvertiser.swift`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/Streaming/LanDiscoveryAdvertiser.swift)
- **Subsystem:** Advertises `_castsprint._tcp` via Bonjour mDNS with 4-digit pairing PIN. MediaProjection feeds MediaCodec H.264 encoder on Android.

### 6. Android Wireless ADB
- **Engine:** `ADBDeviceManager.pairWirelessDevice` / `connectWirelessDevice`
- **Subsystem:** Official Android 11+ wireless debugging using TLS-authenticated `adb pair <ip>:<port> <code>` followed by `adb connect`.
