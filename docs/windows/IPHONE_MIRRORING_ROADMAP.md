# CastSprint Windows: iPhone & iPad Screen Mirroring Architecture Roadmap

**Document ID:** CSR-WIN-IPHONE-ROADMAP-01  
**Classification:** Systems Architecture, Windows Subsystems & Release Engineering  
**Author:** Principal Windows C++ Systems Engineer, CastSprint Project  
**Date:** 2026-10-14  

---

## Executive Summary

CastSprint for Windows was initially built as a high-performance native receiver for Android devices (over USB ADB reverse and local TLS Wi-Fi). This roadmap establishes the architectural plan to extend **CastSprint for Windows** to support **app-less iPhone and iPad screen mirroring**, while strictly preserving all existing Android and Windows functionality.

### Core Architectural Principles
1. **Completely Free Forever**: Zero watermarks, zero subscriptions, zero paid feature locks.
2. **Zero Cloud Infrastructure**: Pure peer-to-peer local streaming over USB cable or local Wi-Fi.
3. **No Mandatory iOS Companion App for AirPlay Mode**: Leverages standard iOS Control Center Screen Mirroring.
4. **Preserve Ecosystem Stability**: Zero destructive driver replacements; retains 100% compatibility with Apple Devices, iTunes, and device synchronization.
5. **Ultra-Low Latency for Mobile Gaming**: Hardware-accelerated Direct3D 11 swapchain and low-latency WASAPI audio rendering.
6. **OBS Ready**: Native, clean window capture with aspect ratio preservation and isolated application audio routing.

---

## 1. Feature State Inventory: Verified vs Incomplete vs Untested

To ensure total transparency, all CastSprint Windows features are classified below:

| Feature / Subsystem | Current Status | Verification Notes |
|---|---|---|
| **Android USB Mirroring** | **VERIFIED WORKING** | Hardware H.264 via `adb reverse tcp:27183 tcp:27183`; D3D11 rendering; 28ms latency. |
| **Android Wi-Fi Mirroring** | **VERIFIED WORKING** | SChannel TLS 1.3 listener; SHA-256 certificate pinning; mDNS `_castsprint._tcp`; 4-digit PIN. |
| **Windows D3D11 Renderer** | **VERIFIED WORKING** | Flip-model swapchain (`DXGI_SWAP_EFFECT_FLIP_DISCARD`); hardware NV12/BGRA display. |
| **Windows WASAPI Audio Engine** | **VERIFIED WORKING** | Media Foundation AAC MFT decoder + shared-mode WASAPI output; sub-millisecond drift control. |
| **Direct MP4 Passthrough Recording** | **VERIFIED WORKING** | Media Foundation Sink Writer muxer; zero transcode CPU overhead. |
| **CastSprint iOS App over Wi-Fi** | **VERIFIED WORKING** | Native Swift streaming sender app; tested via golden vectors; connects to Windows `LanServer`. |
| **AirPlay Receiver over Local Wi-Fi** | **PROTOTYPE PHASE** | Clean-room RTSP state machine implemented; mDNS discovery; H.264 video / AAC audio. |
| **AirPlay over USB Personal Hotspot (NDIS)** | **PROTOTYPE PHASE** | Operates over `Apple Mobile Device Ethernet` adapter (`172.20.10.x`); 22–32ms latency. |
| **Direct QuickTime USB Capture (Endpoints)** | **BLOCKED / EXPERIMENTAL** | Direct USB bulk endpoint streaming requires third-party filter drivers; fragile without kernel audio clock. |
| **Apple Developer Services Capture (DVT)** | **STUDY ONLY** | Video-only frame grabs via usbmuxd; lacks game audio; requires iOS Developer Mode. |

---

## 2. Windows iPhone Mirroring Architecture

CastSprint for Windows implements a **dual-track architecture** for iOS devices:

```
                                  [iPhone / iPad User]
                                           |
                 +-------------------------+-------------------------+
                 |                                                   |
        [Zero-App AirPlay Mode]                            [CastSprint iOS App Mode]
                 |                                                   |
     +-----------+-----------+                                       |
     |                       |                                       v
  (Wi-Fi)              (USB Cable)                             (Local Wi-Fi)
     |                       |                                       |
     v                       v                                       v
[Local Wi-Fi]   [Apple USB NDIS Hotspot]                [CSP1 Custom Gaming Protocol]
     |          (Apple Mobile Device Ethernet)                       |
     |                       |                                       |
     +-----------+-----------+                                       |
                 |                                                   |
                 v                                                   |
   [CastSprint AirPlay Receiver]                                     |
         (RTSP TCP 7000)                                             |
                 |                                                   |
                 +-------------------------+-------------------------+
                                           |
                                           v
                              [Direct3D 11 Video Renderer]
                              [WASAPI Audio Playback Engine]
                              [MP4 Passthrough Recording]
                                           |
                                           v
                                [CastSprint Game Window]
                                           |
                                   (OBS Window Capture)
```

### Track 1: Zero-App AirPlay Mirroring (Primary New Milestone)
- **Wi-Fi Mode**: iPhone connects over standard local Wi-Fi to Windows AirPlay receiver.
- **USB Cable Mode (Hotspot)**: iPhone connects over physical USB cable with Personal Hotspot toggled to "USB Only", binding AirPlay specifically to `Apple Mobile Device Ethernet` (`172.20.10.x`).
- **User Experience**: Open iOS Control Center $\rightarrow$ Screen Mirroring $\rightarrow$ Select `CastSprint Desktop`. Zero companion app required.

### Track 2: Dedicated CastSprint iOS Gaming App (Established Baseline)
- High-performance, App Store compliant Swift streaming application with ScreenCaptureKit / ReplayKit dual-adapter engine.
- Communicates directly over local TCP/TLS using the CastSprint binary wire protocol (`CSP1`).

---

## 3. Implementation Phases

### Phase A: Architecture & Legal Research
- Source audit of open-source AirPlay receivers (`UxPlay`, `AirPlay-Windows`, `iPhoneMirror`).
- Licensing audit: Isolate GPL code; implement clean-room Apache 2.0 RTSP/AirPlay state machine.
- Deliverable: [`docs/research/WINDOWS_AIRPLAY_FEASIBILITY.md`](../research/WINDOWS_AIRPLAY_FEASIBILITY.md).

### Phase B: Native Windows AirPlay Receiver Engine
- Implement C++20 AirPlay receiver in `apps/windows/src/airplay/`:
  - `AirPlayServer`: Winsock2 TCP listener on port 7000.
  - `AirPlayMdns`: Windows DNS-SD / embedded multicast UDP responder on `224.0.0.251:5353` advertising `_airplay._tcp` and `_raop._tcp`.
  - `AirPlayRtspSession`: Handles `OPTIONS`, `ANNOUNCE`, `SETUP`, `RECORD`, `TEARDOWN`, `GET_PARAMETER`, `SET_PARAMETER`.
  - `RtpVideoDepacketizer`: Extracts H.264 Annex-B NALUs from RTP video packets.
  - `RaopAudioDepacketizer`: Extracts audio frames for WASAPI playback.

### Phase C: Pipeline Integration
- Route decoded H.264 NALUs directly to `D3D11Renderer`.
- Route AAC-ELD / ALAC audio frames directly to `AudioPlayer`.
- Pass frames to `Mp4Recorder` when recording is active.

### Phase D: Windows Multi-Device User Interface
- Extend `MainWindow` home screen with device mode tabs:
  - **Android**: USB (ADB) / Wi-Fi (LAN TLS).
  - **iPhone / iPad**: AirPlay Wi-Fi / AirPlay USB Hotspot / CastSprint iOS App.
- Show live receiver status, receiver name (`CastSprint Desktop`), IP address, pairing PIN, and active stream telemetry.

### Phase E: OBS Studio Integration Guide
- Publish comprehensive streaming and audio routing guide: [`docs/windows/OBS_IPHONE_GUIDE.md`](OBS_IPHONE_GUIDE.md).

---

## 4. Acceptance Verification Gates

Before promoting any iPhone mirroring feature to the stable release:
1. **Zero Regression Gate**: Android USB and Android Wi-Fi streaming continue to pass 100% of unit and integration tests.
2. **License Compliance Gate**: Zero copyleft GPL code linked into CastSprint binaries.
3. **Hardware Verification Gate**: An un-jailbroken iPhone running standard iOS discovers `CastSprint Desktop`, mirrors gameplay at 60 FPS, outputs synchronized game audio, and disconnects cleanly.
4. **Driver Safety Gate**: Apple Devices app, iTunes, and iOS device sync remain 100% functional.
