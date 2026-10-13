# CastSprint Apple Platform Architecture

This document defines the cross-platform unified media architecture extending CastSprint to **macOS** (Desktop Receiver & Capture Host) and **iOS** (Screen & Audio Capture Sender).

---

## 1. Unified Multi-Source Media Architecture

CastSprint decouples capture mechanisms, transport protocols, and presentation rendering through a unified interface contract. This allows desktop receivers (Windows and macOS) to handle diverse mobile input streams without duplicate UI or rendering logic.

```
+----------------------------------------------------------------------------------------------------+
|                                      CAPTURE SOURCES                                               |
+-----------------------------+-----------------------------+----------------------------------------+
| 1. Android Stream           | 2. iPhone USB Capture       | 3. iOS LAN Stream                      |
|    - MediaProjection        |    - CoreMediaIO            |    - ReplayKit / ScreenCaptureKit      |
|    - MediaCodec H.264 / AAC |    - AVFoundation           |    - VideoToolbox H.264 / AAC          |
|    - TCP / TLS (CSP1)       |    - NO COMPANION APP       |    - Network.framework TLS (CSP1)      |
+-----------------------------+-----------------------------+----------------------------------------+
                              |                             |
                              v                             v
+----------------------------------------------------------------------------------------------------+
|                                    UNIFIED PIPELINE ADAPTERS                                       |
+------------------------------------+---------------------------------------------------------------+
|  EncodedVideoInput                 |  NativeSampleBufferInput                                      |
|  - Ingests Annex-B NALUs           |  - Ingests CMSampleBufferRef (CVPixelBuffer / AudioBufferList) |
|  - Packet demuxing                 |  - Direct hardware surface handoff                            |
+------------------------------------+---------------------------------------------------------------+
|  AudioInput (AAC / Opus / PCM s16le / CMSampleBuffer Audio)                                         |
+----------------------------------------------------------------------------------------------------+
|  DeviceDiscoveryProvider (mDNS / USB Host Monitoring / ADB Reverse)                                |
+----------------------------------------------------------------------------------------------------+
|  SessionController (State Machine, PIN Pairing, Heartbeat RTT, Diagnostics)                       |
+----------------------------------------------------------------------------------------------------+
                                     |
                                     v
+----------------------------------------------------------------------------------------------------+
|                                      DESKTOP MEDIA SINKS                                           |
+-----------------------------------------+----------------------------------------------------------+
|  Windows Sinks                          |  macOS Sinks                                             |
|  - Direct3D 11 Flip-Discard Surface     |  - Metal / MetalKit Zero-Copy Texture Pipeline           |
|  - Media Foundation AAC MFT             |  - VideoToolbox Hardware Decompressor                    |
|  - WASAPI Shared Low-Latency Audio      |  - CoreAudio HAL Output Unit (Sub-10ms)                  |
|  - MF SinkWriter MP4 Recording          |  - AVAssetWriter MP4 Recording (Zero-Transcode)          |
|  - OBS Window Capture (WGC Hook)        |  - OBS Window Capture / Syphon Surface                    |
+-----------------------------------------+----------------------------------------------------------+
```

---

## 2. Core Architectural Difference: Encoded Stream vs. Native SampleBuffer

A critical architectural distinction exists between network-streamed sources (Android and iOS LAN) and macOS USB iPhone capture:

1. **Network Streams (`EncodedVideoInput`)**:
   - Produce packetized, hardware-compressed video (H.264 Annex-B NAL units) and audio frames (AAC-LC) wrapped in CastSprint Protocol v1 (`CSP1`) messages.
   - Require receiver-side demuxing, jitter buffering, and hardware decoding before display.
2. **macOS iPhone USB Capture (`NativeSampleBufferInput`)**:
   - Uses native macOS `CoreMediaIO` and `AVFoundation` hardware capture.
   - Directly produces uncompressed or muxed `CMSampleBuffer` instances containing `CVPixelBuffer` frames (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` / NV12) and uncompressed Linear PCM audio buffers.
   - **No mobile companion app is installed on the iPhone.**
   - Bypasses network transport and codec decompression overhead completely, enabling tournament-grade glass-to-glass latency (<15 ms).

---

## 3. Unified Media Pipeline Contracts

To ensure consistency across Windows C++ and macOS Swift engines, all platform implementations adhere to standard contract interfaces:

### `EncodedVideoInput`
- **Responsibility**: Ingests incoming H.264/HEVC compressed bitstreams from network sockets or USB reverse pipes.
- **Contract**:
  - `onVideoConfig(config: VideoConfig)`: Initializes or reconfigures the video decompressor.
  - `onVideoFrame(frame: VideoFrame)`: Delivers an access unit with monotonic PTS, keyframe flags, and payload.

### `NativeSampleBufferInput`
- **Responsibility**: Ingests direct hardware sample buffers from macOS `AVCaptureSession`.
- **Contract**:
  - `onVideoSampleBuffer(sampleBuffer: CMSampleBuffer)`: Extracts `CVPixelBuffer` for immediate Metal presentation or pass-through recording.
  - `onAudioSampleBuffer(sampleBuffer: CMSampleBuffer)`: Extracts `AudioBufferList` for CoreAudio playback.

### `AudioInput`
- **Responsibility**: Ingests compressed or uncompressed audio packets.
- **Contract**:
  - `onAudioConfig(config: AudioConfig)`: Configures sample rate (e.g. 48,000 Hz), channels (stereo), and format.
  - `onAudioFrame(frame: AudioFrame)`: Delivers audio payload with microsecond PTS.

### `DeviceDiscoveryProvider`
- **Responsibility**: Discovers available mobile devices across physical USB ports and local subnets.
- **Contract**:
  - `startDiscovery()` / `stopDiscovery()`
  - `onDeviceAppeared(device: DiscoveredDevice)`
  - `onDeviceDisappeared(deviceId: String)`

### `ConnectionTransport`
- **Responsibility**: Byte stream abstraction for USB reverse tunnels and TLS LAN sockets.
- **Contract**:
  - `connect(endpoint: String, options: TransportOptions)`
  - `send(data: UnsafeRawBufferPointer)`
  - `disconnect()`

### `SessionController`
- **Responsibility**: Oversees connection handshakes, authentication PIN verification, heartbeat echo calculations, and session statistics.

### `VideoRenderer`
- **Responsibility**: Displays video frames with correct aspect ratio and zero tearing.
- **Windows**: `D3D11Renderer` using `DXGI_SWAP_EFFECT_FLIP_DISCARD`.
- **macOS**: `MetalVideoRenderer` using `CAMetalLayer` and custom double-buffered Metal compute/render pipeline.

### `AudioOutput`
- **Responsibility**: Low-latency hardware audio playback.
- **Windows**: WASAPI shared-mode stream.
- **macOS**: CoreAudio `AudioUnit` (HAL Output).

### `RecordingSink`
- **Responsibility**: Writes audio/video directly to disk without CPU/GPU re-encoding penalties.
- **Windows**: Media Foundation Sink Writer.
- **macOS**: `AVAssetWriter` configured for passthrough muxing.

---

## 4. Clock Synchronization & Monotonic Timestamps

All capture sources normalize timestamps into **monotonic microsecond timestamps (`pts_us`)**:
- **Android**: `MediaCodec.BufferInfo.presentationTimeUs` (monotonic hardware clock).
- **iOS Sender**: `CMSampleBufferGetPresentationTimeStamp` converted to microseconds via `CMTimeGetSeconds`.
- **macOS USB Capture**: `CMSampleBufferGetOutputPresentationTimeStamp` mapped into host `mach_absolute_time()` domain.

Drift between audio and video clocks is continuously smoothed by [`AvSynchronizer`](../../native/sync/av_sync.hpp), preventing synchronization divergence during multi-hour gaming streams.

---

## 5. Memory Management & Zero-Copy Contracts

- **macOS Pipeline**:
  - Video frames captured via `AVCaptureSession` are delivered as retained `CMSampleBuffer` references.
  - Metal textures are created directly from `CVPixelBuffer` via `CVMetalTextureCacheCreateTextureFromImage`, avoiding any byte copies between system memory and GPU VRAM.
- **iOS Sender App**:
  - ReplayKit Broadcast Extension is restricted to a **50 MB physical memory ceiling**.
  - `CVPixelBuffer` instances delivered by ReplayKit are passed directly into `VTCompressionSession` for hardware encoding without intermediate buffer allocations.
