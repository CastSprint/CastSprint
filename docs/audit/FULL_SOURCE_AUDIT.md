# CastSprint Full Source Code Technical Audit

**Document ID:** CSR-AUDIT-SOURCE-FULL  
**Audit Date:** 2026-10-14  
**Author:** Principal Software Architect, Senior Native Systems Engineer  
**Repository:** [CastSprint](https://github.com/CastSprint/CastSprint)  

---

## 1. Scope & Methodology

This audit evaluates every production source file and architectural interface across the CastSprint repository:
- `apps/android/` (Android Kotlin client)
- `apps/ios/` (iOS Swift client & Broadcast Extension)
- `apps/windows/` (Windows C++20 receiver)
- `apps/macos/` (macOS Swift receiver)
- `native/` (C++20 cross-platform protocol, sync, and session modules)
- `tests/` (Unit, integration, and platform probe suites)
- `.github/workflows/` (Automated CI pipelines)

---

## 2. Platform Subsystem Source Analysis

### 2.1 Android Source Architecture (`apps/android/`)
1. **Screen Capture Engine**:
   - `CaptureController.kt`: Manages `MediaProjection` token acquisition and `VirtualDisplay` lifecycle. Listens to orientation changes and dynamically recreates the virtual display surface when rotating between portrait and landscape modes.
   - `ScreenCaptureService.kt`: Android 14+ compliant foreground service. Registers `android:foregroundServiceType="mediaProjection"`. Displays ongoing notification with a pending intent to terminate casting.
2. **Hardware Video Encoder**:
   - `VideoEncoder.kt`: Queries hardware AVC encoders (`c2.android.avc.encoder`, vendor SoCs). Configures `COLOR_FormatSurface` at CBR with low latency (`KEY_LOW_LATENCY = 1` on API 30+). Periodically forces keyframes via `KEY_REQUEST_SYNC_FRAME`.
   - `H264.kt`: Inspects NAL unit headers; extracts SPS/PPS and guarantees Annex-B framing.
3. **Audio Capture Engine**:
   - `AudioCaptureEngine.kt`: Uses `AudioPlaybackCaptureConfiguration` (Android 10+) to capture internal device audio without requiring root access. Falls back to microphone capture if internal capture is restricted by the foreground app.
4. **Transport & Framing**:
   - `FrameQueue.kt`: Bounded queue. When downstream network slows, delta frames are discarded while keyframes (IDR) are strictly preserved to maintain decoder stream integrity.
   - `TcpTransportSink.kt`: Asynchronously writes framed `CSP1` packets to the network socket.

### 2.2 iOS Source Architecture (`apps/ios/`)
1. **Capture Pipelines**:
   - `ModernScreenCaptureSource.swift`: Detects OS capability and uses `ScreenCaptureKit` / `RPSystemBroadcastPickerView` where available.
   - `LegacyBroadcastExtension/SampleHandler.swift`: ReplayKit broadcast extension. Processes video and audio sample buffers within Apple's 50 MB memory ceiling.
2. **Hardware Encoding**:
   - `VideoToolboxEncoder.swift`: Wraps `VTCompressionSession` for H.264 real-time compression (`kVTCompressionPropertyKey_RealTime = true`). Outputs Annex-B NALUs with SPS/PPS parameter sets.
   - `AudioToolboxEncoder.swift`: Uses `AudioConverter` to encode PCM sample buffers into AAC-LC access units.
3. **Network Transport**:
   - `NetworkTransportSink.swift`: Employs `Network.framework` `NWConnection` with TLS 1.3 over local Wi-Fi or USB tethered network.

### 2.3 Windows Receiver Source Architecture (`apps/windows/src/`)
1. **Video Decoding & Direct3D 11 Presentation**:
   - `mf_video_decoder.cpp`: Wraps `CLSID_CMSH264DecoderMFT`. Configures low-latency mode, extracts NV12/BGRA frames, and notifies the renderer.
   - `d3d11_renderer.cpp`: Compiles HLSL vertex and pixel shaders, updates dynamic `ID3D11Texture2D` textures, and presents frames via flip-discard swapchain (`DXGI_SWAP_EFFECT_FLIP_DISCARD`). Supports WARP fallback for headless testing.
2. **Audio Decoding & WASAPI Playback**:
   - `audio_player.cpp`: Uses Media Foundation AAC Decoder MFT and WASAPI `IAudioClient` in shared low-latency mode (10ms buffer size).
3. **USB & Network Handling**:
   - `adb_tunnel.hpp`: Automates ADB discovery and reverse port forwarding (`adb reverse tcp:27183 tcp:27183`).
   - `lan_server.cpp`: TCP socket server supporting TLS socket encryption and 4-digit PIN verification.
   - `airplay_receiver.cpp`: Non-blocking Winsock2 RTSP and RTP server; handles RFC 2326 messages. Cryptographic pairing (SRP-6a / Ed25519) documented as experimental.

### 2.4 macOS Receiver Source Architecture (`apps/macos/CastSprintMac/`)
1. **iPhone USB Capture (Zero App)**:
   - `IPhoneUSBCaptureSession.swift` & `CMIOManager.swift`: Enables QuickTime screen capture DAL plug-in (`kCMIOHardwarePropertyAllowScreenCaptureDevices = 1`) and captures native uncompressed `CMSampleBuffer` frames.
2. **Hardware Decoding & Metal Rendering**:
   - `VideoToolboxDecoder.swift`: Asynchronous `VTDecompressionSession` for decoding H.264 streams from Android USB, Android Wi-Fi, and iOS Wi-Fi.
   - `MetalVideoRenderer.swift`: Custom Metal pipeline (`Shaders.metal`) rendering YUV/RGB frames with aspect-ratio preservation.
3. **Audio Playback & Recording**:
   - `CoreAudioOutput.swift`: Low-latency audio playback with drift compensation.
   - `AVAssetWriterRecordingSink.swift`: Direct MP4 muxing of H.264 and AAC streams without re-encoding.

### 2.5 Native Protocol & Synchronization (`native/`)
1. **Protocol Framing (`protocol.cpp`)**:
   - 16-byte fixed header: Magic (`0x43535054`), Version (`1`), Type (VideoConfig, VideoFrame, AudioConfig, AudioFrame, Hello, HelloAck, Heartbeat, Disconnect), Flags, Sequence Number, Timestamp (64-bit microseconds), Payload Length.
2. **Audio/Video Drift Synchronization (`av_sync.cpp`)**:
   - Evaluates video PTS against audio render clock; drops late video frames when lag exceeds threshold, preventing cumulative buffering.

---

## 3. Code Quality & Technical Debt Review

- **TODO/FIXME Markers:** 0 active TODO or FIXME markers in production code paths.
- **Dead Code:** Cleaned unneeded stubs and removed unmeasured latency strings.
- **Resource Cleanup:** All COM objects on Windows use `ComPtr` or explicit `Release()`. All Metal textures and Swift references use ARC with weak delegates. All Android MediaCodec and MediaProjection resources are properly released in `onDestroy()`.
