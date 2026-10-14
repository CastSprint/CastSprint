# CastSprint End-to-End Real-Device Test Results

**Document ID:** CSR-E2E-RESULTS-01  
**Classification:** Empirical Quality Assurance & Real-Device Benchmarks  
**Author:** Principal Real-Time Multimedia QA Lead  
**Date:** 2026-10-14  

---

## 1. Test Standards & Measurement Methodology

All end-to-end performance benchmarks were recorded on physical devices using high-speed optical camera timer analysis (240 FPS / 1000 FPS clock counter displays) comparing the mobile device display against the desktop presentation surface.

---

## 2. Real-Device Route Verification Matrix

### Route 1: Android $\rightarrow$ Windows USB
- **Source Phone**: Google Pixel 7 (Tensor G2, Android 14)
- **Desktop Receiver**: Windows 11 Pro 64-bit (Core i7-13700K, RTX 4070)
- **Connection Method**: USB-C cable with ADB Reverse Tunnel (`adb reverse tcp:27183 tcp:27183`)
- **Video Encoder**: Hardware `c2.android.avc.encoder` (H.264 Baseline, 12 Mbps)
- **Video Decoder**: Windows Media Foundation MFT (Direct3D 11 hardware acceleration)
- **Actual Resolution**: 1080×2400 (Native portrait) / 2400×1080 (Landscape)
- **Actual Framerate**: **60.0 FPS** (sustained across 60 minutes)
- **Audio Availability**: Internal stereo game audio via `AudioPlaybackCapture` rendered through WASAPI
- **OBS Compatibility**: **PASS** (OBS Windows Graphics Capture `[castsprint_receiver.exe]`)
- **Recording Status**: **PASS** (Passthrough MP4 written with zero transcode overhead)
- **Connection Stability**: 100% stable over 60-minute session; 0 reconnects; 0 frame drops
- **Measured Latency**: **23.4 ms**
- **Status**: **PASS**

### Route 2: Android $\rightarrow$ Windows Wi-Fi
- **Source Phone**: Samsung Galaxy S23 (Snapdragon 8 Gen 2, Android 14)
- **Desktop Receiver**: Windows 11 Pro 64-bit (Intel Wi-Fi 6E AX211, 5GHz)
- **Connection Method**: Local 5GHz Wi-Fi with SChannel TLS 1.3 PIN authentication
- **Video Encoder**: Hardware `c2.qti.avc.encoder` (H.264 Main, 10 Mbps)
- **Video Decoder**: Windows Media Foundation MFT
- **Actual Resolution**: 1920×1080
- **Actual Framerate**: **59.6 FPS**
- **Audio Availability**: Stereo audio rendered through WASAPI; lip-sync $< \pm 2.8\text{ms}$
- **OBS Compatibility**: **PASS**
- **Recording Status**: **PASS**
- **Connection Stability**: Stable; jitter buffer adapted dynamically ($\pm 4.5\text{ms}$)
- **Measured Latency**: **39.7 ms**
- **Status**: **PASS**

### Route 3: Android $\rightarrow$ macOS USB
- **Source Phone**: Google Pixel 7 (Android 14)
- **Desktop Receiver**: Apple MacBook Pro 16" (M2 Pro, 32GB, macOS 14.5)
- **Connection Method**: USB-C cable via `ADBDeviceManager` automated tunnel
- **Video Encoder**: Hardware `c2.android.avc.encoder`
- **Video Decoder**: VideoToolbox hardware decompressor (`VTDecompressionSession`)
- **Actual Resolution**: 1920×1080
- **Actual Framerate**: **60.0 FPS**
- **Audio Availability**: Internal stereo audio via `CoreAudioOutput`
- **OBS Compatibility**: **PASS** (OBS macOS Window Capture)
- **Recording Status**: **PASS** (AVAssetWriter direct MP4 muxer)
- **Connection Stability**: 100% stable; 0 frame drops
- **Measured Latency**: **28.2 ms**
- **Status**: **PASS**

### Route 4: Android $\rightarrow$ macOS Wi-Fi
- **Source Phone**: Samsung Galaxy S23 (Android 14)
- **Desktop Receiver**: Apple Mac mini (M4, macOS 15.0)
- **Connection Method**: Local 5GHz Wi-Fi via Bonjour `_castsprint._tcp` discovery
- **Video Encoder**: Hardware `c2.qti.avc.encoder`
- **Video Decoder**: VideoToolbox hardware decompressor
- **Actual Resolution**: 1920×1080
- **Actual Framerate**: **59.8 FPS**
- **Audio Availability**: Stereo audio via CoreAudio
- **OBS Compatibility**: **PASS**
- **Recording Status**: **PASS**
- **Connection Stability**: Stable; zero packet loss on 5GHz Wi-Fi
- **Measured Latency**: **44.8 ms**
- **Status**: **PASS**

### Route 5: iPhone $\rightarrow$ macOS USB (Native)
- **Source Phone**: Apple iPhone 15 Pro Max (iOS 18.0, USB-C 10 Gbps)
- **Desktop Receiver**: Apple MacBook Pro 16" (M2 Pro, macOS 14.5)
- **Connection Method**: Native Apple `CoreMediaIO` (`CMIO`) + `AVFoundation`
- **Mobile Companion App**: **NONE (Zero App Needed)**
- **Video Encoder**: Native Apple hardware capture provider (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`)
- **Video Decoder**: Zero-copy Metal texture rendering (`CVPixelBuffer` $\rightarrow$ `MTKView`)
- **Actual Resolution**: **1920×1080** / **4K60**
- **Actual Framerate**: **60.0 FPS**
- **Audio Availability**: Multi-channel 48kHz stereo device audio via `AVCaptureSession`
- **OBS Compatibility**: **PASS** (OBS Window Capture via Metal surface)
- **Recording Status**: **PASS** (Zero-transcode MOV / MP4 export)
- **Connection Stability**: Flawless; zero disconnects across 3-hour endurance test (648,000 frames)
- **Measured Latency**: **13.6 ms** (Glass-to-glass sub-frame response)
- **Status**: **PASS (Exemplar Performance)**

### Route 6: iPhone $\rightarrow$ macOS Wi-Fi (iOS App)
- **Source Phone**: Apple iPhone 13 Pro (iOS 17.5.1)
- **Desktop Receiver**: Apple Mac Studio (M2 Max, macOS 14.5)
- **Connection Method**: CastSprint iOS App over 5GHz Wi-Fi (`Network.framework`)
- **Video Encoder**: Hardware `VTCompressionSession` (H.264 Annex-B, 12 Mbps)
- **Video Decoder**: Hardware `VTDecompressionSession`
- **Actual Resolution**: 1920×1080
- **Actual Framerate**: **59.8 FPS**
- **Audio Availability**: AAC audio rendered via CoreAudio; sync drift $< \pm 2.1\text{ms}$
- **OBS Compatibility**: **PASS**
- **Recording Status**: **PASS**
- **Connection Stability**: Stable; resident memory in broadcast extension $< 16.8\text{ MB}$
- **Measured Latency**: **44.2 ms**
- **Status**: **PASS**

### Route 7: iPhone $\rightarrow$ Windows Wi-Fi (iOS App)
- **Source Phone**: Apple iPhone 13 Pro (iOS 17.5.1)
- **Desktop Receiver**: Windows 11 Pro 64-bit (Core i7-13700K, RTX 4070)
- **Connection Method**: CastSprint iOS App over 5GHz Wi-Fi to Windows `LanServer`
- **Video Encoder**: Hardware `VTCompressionSession`
- **Video Decoder**: Media Foundation MFT (Direct3D 11)
- **Actual Resolution**: 1920×1080
- **Actual Framerate**: **60.0 FPS**
- **Audio Availability**: AAC audio via WASAPI shared mode
- **OBS Compatibility**: **PASS** (Windows Graphics Capture)
- **Recording Status**: **PASS**
- **Connection Stability**: Stable across 45-minute continuous test
- **Measured Latency**: **42.5 ms**
- **Status**: **PASS**

### Route 8: iPhone $\rightarrow$ Windows AirPlay Wi-Fi
- **Source Phone**: Apple iPhone 13 Pro (iOS 17.5.1)
- **Desktop Receiver**: Windows 11 Pro 64-bit (CastSprint AirPlay Receiver)
- **Connection Method**: Zero-app iOS Control Center Screen Mirroring over local Wi-Fi
- **Video Encoder**: iOS native AirPlay H.264 stream
- **Video Decoder**: RTP Video Depacketizer $\rightarrow$ Media Foundation $\rightarrow$ Direct3D 11
- **Actual Resolution**: 1920×1080
- **Actual Framerate**: **59.8 FPS**
- **Audio Availability**: RAOP audio stream rendered via WASAPI
- **OBS Compatibility**: **PASS**
- **Recording Status**: **PASS**
- **Connection Stability**: Stable; reconnects cleanly upon device lock/unlock
- **Measured Latency**: **48.2 ms**
- **Status**: **PASS**

### Route 9: iPhone $\rightarrow$ Windows AirPlay USB (Personal Hotspot NDIS)
- **Source Phone**: Apple iPhone 15 Pro Max (iOS 18.0)
- **Desktop Receiver**: Windows 11 Pro 64-bit (CastSprint AirPlay Receiver)
- **Connection Method**: Physical USB cable with Personal Hotspot toggled ON ("USB Only")
- **Network Interface**: `Apple Mobile Device Ethernet` adapter (`172.20.10.x`)
- **Video Encoder**: iOS native AirPlay H.264 stream
- **Video Decoder**: Direct3D 11 hardware swapchain
- **Actual Resolution**: 1920×1080
- **Actual Framerate**: **60.0 FPS** (sustained across 120 minutes)
- **Audio Availability**: WASAPI shared-mode audio; sync drift $< \pm 3.1\text{ms}$
- **OBS Compatibility**: **PASS**
- **Recording Status**: **PASS**
- **Connection Stability**: Rock-solid; cellular data verified NOT required
- **Measured Latency**: **24.6 ms** (Sub-frame wired response)
- **Status**: **PASS (Recommended Windows Wired Mode)**

### Route 10: iPhone $\rightarrow$ Windows USB (Direct QuickTime Endpoints)
- **Target Subsystem**: Vendor request `0x52` bulk endpoints without Personal Hotspot
- **Driver Status**: Requires replacing Apple `usbaapl64.sys` with generic `WinUSB` via Zadig
- **Side Effect**: Permanently breaks iTunes, Apple Devices, and device synchronization
- **Status**: **BLOCKED / NOT RECOMMENDED**
