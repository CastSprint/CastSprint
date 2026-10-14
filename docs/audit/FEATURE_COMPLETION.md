# CastSprint Feature Completion Status

**Document ID:** CSR-FEATURES-01  
**Audit Date:** 2026-10-14  
**Author:** Principal Software Architect, Native Systems Engineer  
**Repository:** [CastSprint](https://github.com/CastSprint/CastSprint)  

---

## 1. Feature Taxonomy

In accordance with strict release engineering rules, all features and connection routes are classified under one of four unambiguous statuses:
- **`SUPPORTED`**: Feature is fully implemented, verified via automated test suites and platform contracts, and ready for production use.
- **`EXPERIMENTAL`**: Feature code exists and builds, but protocol negotiations or hardware environments are in research/preview mode.
- **`BLOCKED`**: Feature cannot be implemented without violating copyright, third-party copyleft licenses (GPL), or kernel driver stability.
- **`NOT_IMPLEMENTED`**: Feature is planned or desired, but no functional code exists in the repository.

---

## 2. Cross-Platform Feature Completion Matrix

| Platform / Subsystem | Feature Description | Implementation Path | Status | Verification Notes |
|---|---|---|:---:|---|
| **Android** | Screen Capture | `MediaProjection` + `VirtualDisplay` | `SUPPORTED` | Full user consent lifecycle, foreground service, orientation aware. |
| **Android** | Hardware H.264 Encoding | `MediaCodec` (Surface input) | `SUPPORTED` | Hardware CBR encoding, low latency flag, Annex-B output. |
| **Android** | Internal Game Audio | `AudioPlaybackCapture` (API 29+) | `SUPPORTED` | Captures game audio; respects Android manifest capture restrictions. |
| **Android** | USB Mirroring | TCP socket via `adb reverse` | `SUPPORTED` | Automatic port forwarding on port 27183. |
| **Android** | Secure LAN Streaming | TLS 1.3 pinned socket connection | `SUPPORTED` | SHA-256 certificate fingerprint verification, 4-digit PIN pairing. |
| **iOS** | Screen Capture (Modern) | `ScreenCaptureKit` / `RPSystemBroadcastPickerView` | `SUPPORTED` | Official system broadcast modal, orientation aware. |
| **iOS** | Screen Capture (Legacy) | `RPBroadcastSampleHandler` | `SUPPORTED` | ReplayKit Broadcast Extension, verified under 25 MB dirty memory. |
| **iOS** | Hardware H.264 Encoding | `VTCompressionSession` (VideoToolbox) | `SUPPORTED` | Hardware real-time compression, Annex-B SPS/PPS generation. |
| **iOS** | Audio Capture & Encoding | `AudioConverter` (AudioToolbox) | `SUPPORTED` | Encodes PCM system audio to AAC-LC access units. |
| **iOS** | Secure LAN Streaming | `Network.framework` TLS 1.3 | `SUPPORTED` | Connects to Windows/macOS desktop receivers over local Wi-Fi. |
| **macOS** | App-less iPhone USB Capture | `CoreMediaIO` (`CMIO`) + `AVCaptureSession` | `SUPPORTED` | Native QuickTime-compatible zero-app capture, delivers CMSampleBuffers. |
| **macOS** | Hardware Video Decoding | `VTDecompressionSession` | `SUPPORTED` | Hardware H.264 decompression for Android and iOS network streams. |
| **macOS** | GPU Video Rendering | `Metal` Shaders + `MTKView` | `SUPPORTED` | Custom Metal quad shaders with aspect ratio letterboxing/pillarboxing. |
| **macOS** | Audio Output | `CoreAudio` / `AVAudioEngine` | `SUPPORTED` | Low-latency playback with drift compensation. |
| **macOS** | Android USB Mirroring | ADB reverse + local TCP receiver | `SUPPORTED` | Automated via `ADBDeviceManager.swift`. |
| **macOS** | MP4 Local Recording | `AVAssetWriter` | `SUPPORTED` | Direct synchronized multiplexing of H.264 and AAC streams. |
| **Windows** | Direct3D 11 Video Presentation| `Direct3D 11` Flip-Model Swapchain | `SUPPORTED` | Dynamic texture mapping, HLSL shaders, WARP software fallback. |
| **Windows** | Hardware Video Decoding | Media Foundation H.264 MFT | `SUPPORTED` | Low-latency decoding, dynamic format change handling, Annex-B support. |
| **Windows** | WASAPI Audio Playback | `IAudioClient` shared low-latency mode | `SUPPORTED` | Media Foundation AAC decoder, automatic endpoint recovery. |
| **Windows** | Android USB Mirroring | ADB reverse + `AdbTunnel` automation | `SUPPORTED` | Auto-detects `adb.exe`, sets up reverse port forwarding. |
| **Windows** | iOS Companion App Receiver | `LanServer` TCP receiver + PIN auth | `SUPPORTED` | Primary production route for iPhone to Windows mirroring. |
| **Windows** | MP4 Local Recording | Media Foundation Sink Writer | `SUPPORTED` | Direct passthrough multiplexing with monotonic microsecond PTS. |
| **Windows** | App-less AirPlay Receiver | Clean-room RTSP/RTP receiver | `EXPERIMENTAL` | RTSP state machine built; SRP-6a / Ed25519 pairing cryptography pending. |
| **Windows** | iPhone USB Personal Hotspot | Apple NDIS Adapter (`172.20.10.x`) | `EXPERIMENTAL` | Supported via CastSprint iOS app; AirPlay route experimental. |
| **Windows** | Direct USB iPhone Mirroring | Raw USB bulk endpoints (`WinUSB`) | `BLOCKED` | Overriding Apple `usbaapl64.sys` driver breaks system sync/iTunes. |
| **OBS Integration** | Window / Game Capture | OBS Studio 30+ Compatibility | `SUPPORTED` | Stable window class and DirectX 11 / Metal rendering pipelines. |

---

## 3. Desktop Application Architecture

CastSprint enforces **one unified desktop receiver per desktop OS**:
- **CastSprint Windows (`CastSprint.exe`)**: Unifies Android USB, Android Wi-Fi, iPhone iOS App Wi-Fi, and Experimental AirPlay into a single C++20 Win32 application.
- **CastSprint macOS (`CastSprint.app`)**: Unifies iPhone USB (CoreMediaIO), Android USB (ADB), Android Wi-Fi, and iPhone Wi-Fi into a single Swift/Metal application.
