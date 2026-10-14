# iOS Capture Capability & Availability Matrix

This document provides a comprehensive technical evaluation of screen capture technologies on Apple platforms, establishing the architecture, capability gating, and App Store compliance strategy for CastSprint iOS.

---

## 1. Capability & Availability Matrix

| Feature / Subsystem | Legacy ReplayKit (`RPBroadcastSampleHandler`) | Modern ScreenCaptureKit (`SCStream` / `SCContentSharingPicker`) |
|:---|:---:|:---:|
| **Minimum iOS Version** | **iOS 12.0+** (Universal App Store compatibility) | **iOS 27.0+** (Published Apple sample) / macOS 14+ |
| **Availability on iOS 14 – 26** | **Available & Operational** | **Unavailable** in public iOS SDKs below iOS 27 |
| **System Content Picker** | `RPSystemBroadcastPickerView` | `SCContentSharingPicker` |
| **Execution Context** | Broadcast Upload Extension (`com.apple.broadcast-services-upload`) | Containing Host App Process |
| **Memory Ceiling** | **Strict 50 MB physical RAM ceiling** | Standard App Memory Budget (~2 GB) |
| **Background Screen Capture** | **Supported** via system broadcast daemon across all apps | Requires system background screen-capture capability |
| **Game Audio Capture** | **Supported** (`RPSampleBufferType.audioApp` 48kHz PCM) | Supported (`SCStreamOutputType.audio`) |
| **Microphone Commentary** | **Supported** (`RPSampleBufferType.audioMic`, explicit consent) | Supported (with separate permission) |
| **Protected / DRM Content** | Blacked out automatically by system compositor | Blocked by system window capture rules |
| **App Store Review Status** | **100% Public API & Compliant** | Public API on supported target versions |

---

## 2. Technical Findings from Apple SDK Audit

### 2.1 Xcode 26.5 & iOS SDK Inspection
- **Xcode Version**: Xcode 26.5 (Build 17F42), Swift 6.3.2.
- **Installed iOS SDK**: `iPhoneOS26.5.sdk`.
- **Installed macOS SDK**: `MacOSX26.5.sdk`.
- `ReplayKit.framework` is present and functional across all iOS SDK targets, exposing `RPBroadcastSampleHandler`, `RPSystemBroadcastPickerView`, and `RPSampleBufferType`.
- `ScreenCaptureKit.framework` is currently bundled in `MacOSX26.5.sdk` and Mac Catalyst (`System/iOSSupport`), but in pure iOS environments (`iPhoneOS.platform`), Apple's published ScreenCaptureKit sample targets iOS 27 or later.

### 2.2 Dual-Adapter Architecture Recommendation
To ensure immediate App Store viability on currently deployed iPhones and iPads while future-proofing for next-generation iOS versions:
1. **Define Unified Contract**: `ScreenCaptureSource` protocol abstracting permission request, start, pause, resume, stop, orientation, video frames, and audio frames.
2. **`ModernScreenCaptureSource`**:
   - Gated with compile-time `#if canImport(ScreenCaptureKit)` and runtime availability `@available(iOS 27.0, macOS 14.0, *)`.
   - Uses `SCContentSharingPicker` and `SCStream` when running on supported OS releases.
3. **`LegacyBroadcastCaptureSource`**:
   - Implements `RPBroadcastSampleHandler` in a standalone Broadcast Upload Extension (`LegacyBroadcastExtension`).
   - Uses `RPSystemBroadcastPickerView` in the containing SwiftUI app to trigger user-approved capture.
   - Operates strictly under the **50 MB memory ceiling** with immediate hardware encoding and zero buffer accumulation.

---

## 3. App Extension vs. Containing App Division of Responsibilities

```
+-------------------------------------------------------------------------------------------------+
|                                CONTAINING APP (CastSprintIOS)                                   |
|  - SwiftUI User Interface (Home, Pairing, Settings, Active HUD)                                 |
|  - Local Network Discovery (mDNS Bonjour _castsprint._tcp via NWBrowser)                        |
|  - First-time Network & Microphone Permissions Prompts                                          |
|  - Dynamic PIN Entry & QR Code Scanner                                                          |
|  - Shared Configuration Writer: App Group (group.com.castsprint.ios)                            |
|  - System Broadcast Trigger: RPSystemBroadcastPickerView                                        |
+-------------------------------------------------------------------------------------------------+
                                               |
                     App Group UserDefaults    |  (Desktop IP, Port, PIN, Quality Preset)
                                               v
+-------------------------------------------------------------------------------------------------+
|                         BROADCAST EXTENSION (LegacyBroadcastExtension)                          |
|  - RPBroadcastSampleHandler lifecycle (broadcastStarted, broadcastFinished)                     |
|  - Memory Budget: STRICT < 50 MB RAM                                                            |
|  - Video Ingestion: CMSampleBuffer -> VideoToolboxEncoder (H.264 Baseline, Real-time)            |
|  - Audio Ingestion: audioApp -> 48kHz PCM / AAC Packetizer                                      |
|  - Network Transport: NetworkTransportSink (TCP_NODELAY Port 27183, CSP1 Protocol)              |
+-------------------------------------------------------------------------------------------------+
```

---

## 4. App Store Privacy & Permission Requirements

| Permission Key | String Requirement | Context |
|:---|:---|:---|
| `NSLocalNetworkUsageDescription` | *"CastSprint requires access to your local network to discover and stream gameplay to your desktop PC or Mac."* | Required for discovering and connecting to port 27183 on the local subnet. Must be triggered in foreground app. |
| `NSBonjourServices` | Array containing `["_castsprint._tcp"]` | Required to browse Bonjour desktop receivers without triggering firewall blocks. |
| `NSMicrophoneUsageDescription` | *"CastSprint requires microphone access only if you enable live voice commentary while streaming."* | Off by default. Only prompted if user explicitly enables mic in Settings. |
| `NSCameraUsageDescription` | *"CastSprint uses the camera solely to scan desktop pairing QR codes."* | Off by default. Only prompted if user taps "Scan QR Code". |
