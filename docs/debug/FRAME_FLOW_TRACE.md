# CastSprint — Full Source-to-Frame Pipeline Trace

**Document:** `docs/debug/FRAME_FLOW_TRACE.md`  
**Engineer:** Principal macOS Multimedia, Metal & Real-Time Protocol Engineer  
**Status:** Architecture Implemented & Verified in Code  

---

## 1. Complete Source-to-Frame Pipeline Matrix

CastSprint supports four physical streaming pathways. Every pathway terminates in the same low-latency Metal rendering pipeline and is captured by OBS Studio via Window Capture:

| Route | Capture Source | Frame Producer | Transport | Decoder | Presentation |
|---|---|---|---|---|---|
| **iPhone USB** | Unlocked iPhone Display | CoreMediaIO DAL Plugin | USB-C / Lightning Cable | Native CVPixelBuffer (No re-decode required) | Metal `MTKView` |
| **iPhone Wi-Fi** | ReplayKit (`RPSampleBufferType.video`) | VideoToolbox `VTCompressionSession` (H.264) | TCP 27183 (`CSP1` protocol) | VideoToolbox `VTDecompressionSession` | Metal `MTKView` |
| **Android USB** | `VirtualDisplay` / `scrcpy` server | `MediaCodec` (H.264) | ADB USB forward tunnel | VideoToolbox `VTDecompressionSession` | Metal `MTKView` |
| **Android Wi-Fi** | `VirtualDisplay` (`MediaProjection`) | `MediaCodec` (H.264) | TCP 27183 (`CSP1` protocol) | VideoToolbox `VTDecompressionSession` | Metal `MTKView` |

---

## 2. Route 1: iPhone USB (Hardware Direct Path)

```
[ Physical iPhone 15 ]
       │ Unlocked, trusted USB connection
       ▼
[ macOS CoreMediaIO DAL Daemon ]
       │ iOSScreenCapture DAL Plugin (`kCMIOHardwarePropertyAllowScreenCaptureDevices = 1`)
       ▼
[ AVCaptureDevice (Type: .external, isContinuityCamera: false) ]
       │
       ▼
[ IPhoneUSBCaptureSession.swift ]
       │ AVCaptureDeviceInput
       ▼
[ AVCaptureSession ]
       │ AVCaptureVideoDataOutput (pixelFormatType: kCVPixelFormatType_32BGRA or 420YpCbCr8BiPlanarVideoRange)
       ▼
[ captureOutput(_:didOutput:from:) Delegate ]
       │ CMSampleBuffer
       ▼
[ CMSampleBufferGetImageBuffer ]
       │ CVPixelBuffer
       ▼
[ MetalVideoView.swift ]
       │ CVMetalTextureCacheCreateTextureFromImage
       ▼
[ GPU Metal Command Buffer / Render Encoder ]
       │ MTKView (CastSprint Window)
       ▼
[ OBS Studio Window Capture ]
```

### Previous Defect vs. Repaired Checkpoint:
- **Previous Checkpoint (Broken):** `USBDeviceManager.swift` fell back to Continuity Camera when screen device was named `"Shanto’s iPhone 15"`. The `AVCaptureSession` bound to the optical sensor. The user saw their desk/window.
- **Repaired Checkpoint:** `USBDeviceManager.swift` strictly verifies `!dev.isContinuityCamera` and rejects any device with `"Camera"`. Only the DAL screen capture virtual device is accepted.

---

## 3. Route 2 & 4: Wi-Fi Receiver Pathway (Android / iOS)

```
[ Mobile Phone (Android MediaCodec / iOS VideoToolbox) ]
       │ Encoded H.264 NAL Units (SPS, PPS, IDR, P-frames)
       │ Frame Packetizer (4-byte magic "CSP1", type, PTS, length)
       ▼
[ Local Wi-Fi Network ]
       │ TCP Port 27183
       ▼
[ NetworkStreamReceiver.swift ]
       │ Swift NWListener / NWConnection
       │ Packet Header Deserialization: CSPHeader
       ▼
   ┌───┴────────────────────────┐
   │ Check Packet Type          │
   ▼                            ▼
[ 0x03: VIDEO_CONFIG ]       [ 0x04: VIDEO_FRAME ]
   │ SPS / PPS parameter sets   │ Annex-B NAL unit
   ▼                            ▼
[ H264Decoder.swift ] ──────────┘
   │ CMVideoFormatDescriptionCreateFromH264ParameterSets
   │ CMSampleBufferCreateReadyWithImageBuffer / VTDecompressionSessionDecodeFrame
   ▼
[ VideoToolbox Hardware Decoder ]
   │ Decoded CVPixelBuffer (NV12 or BGRA)
   ▼
[ MirroringCoordinator.swift ]
   │ receiverDidReceivePixelBuffer(_:pixelBuffer)
   ▼
[ MetalVideoView.swift ]
   │ Texture Cache -> Metal Fragment Shader -> MTKView
   ▼
[ OBS Studio Window Capture ]
```

---

## 4. Audio Routing & OBS Live Streaming

```
[ Mobile Source Game Audio ]
   │ Android: AudioPlaybackCapture (API 29+) -> PCM 16-bit 48kHz
   │ iOS: ReplayKit audioApp -> AAC / PCM 16-bit
   │ iPhone USB: Inter-Device Audio Mode (IDAM) via Audio MIDI Setup
   ▼
[ CoreAudioOutput.swift / macOS Audio Engine ]
   │ Safe Objective-C Guard (csp_safe_audio_schedule)
   │ AVAudioEngine / Output Node
   ▼
[ macOS System Sound / Aggregate Device ]
   ▼
[ OBS Studio: macOS Audio Capture / Application Audio Capture ]
```

### Truthful Audio State:
- For iPhone USB, Apple's `AVCaptureDevice` video endpoint **does not contain internal game audio**. Apple routes game audio over USB through **Inter-Device Audio Mode (IDAM)** in `Audio MIDI Setup`.
- The UI now truthfully displays `Audio: Enable in Audio MIDI Setup` instead of falsely reporting `Audio: Yes` or using the iPhone's physical microphone.

---

## 5. OBS Studio Integration Verification

1. **Window Selection**:
   In OBS Studio, add a **Window Capture (macOS)** source. Select `[CastSprint] CastSprint`.
2. **Color Profile**:
   Ensure `Color Space: Rec. 709` and `Color Range: Partial/Full` match the Metal view format.
3. **Audio Capture**:
   In OBS Studio, add an **Application Audio Capture (macOS)** source targeting `CastSprint`, or add an **Audio Input Capture** source targeting the iPhone in Inter-Device Audio Mode (IDAM).
4. **Recording Validation**:
   Start a 60-second test recording while playing a fast-paced mobile game.
   Verify the MP4/MKV recording shows zero camera footage, 60 FPS gameplay, and synchronized game audio.
