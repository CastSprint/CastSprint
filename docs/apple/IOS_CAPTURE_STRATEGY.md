# iOS Screen & Audio Capture Strategy

This document details CastSprint's capture, hardware encoding, and network transport architecture for **iOS and iPadOS** devices streaming to Windows and macOS receivers over secure local Wi-Fi.

---

## 1. Capture Mechanisms: ReplayKit vs. ScreenCaptureKit

iOS implements strict sandbox boundaries that prevent standard background applications from recording the system display or other apps. To achieve continuous, high-performance game mirroring, CastSprint uses Apple's official, App Store-approved capture mechanisms:

| Feature | ReplayKit Broadcast Extension | ScreenCaptureKit (iOS 18+) |
|:---|:---|:---|
| **API Class** | `RPBroadcastSampleHandler` | `SCStream` |
| **Compatibility** | iOS 12.0 – iOS 18+ (Universal) | iOS 18.0+ / iPadOS 18.0+ |
| **Execution Context** | Standalone Broadcast Process Extension | In-App / System-Entitled Process |
| **System Memory Limit** | **Strict 50 MB RAM ceiling** | Host Application Budget (~2 GB) |
| **Audio Capture** | Internal Game Audio (`audioApp`) + Mic | Internal Application Audio |
| **User Activation** | `RPSystemBroadcastPickerView` | System Permission Prompt |
| **App Store Viability** | **100% Compliant & Supported** | Restricted by Apple Entitlements |

### Architectural Decision
CastSprint adopts **ReplayKit Broadcast Extension (`LegacyBroadcastExtension`)** as its primary capture engine for broad iOS compatibility (iOS 12 through iOS 18+), while designing an abstraction layer that seamlessly integrates **ScreenCaptureKit** where system entitlements and OS versions permit.

---

## 2. Surviving the 50 MB ReplayKit Memory Ceiling

Apple enforces an aggressive watchdog timer and physical memory limit on Broadcast Extensions: **if memory usage exceeds 50 MB, iOS immediately terminates the extension process with `EXC_RESOURCE (MEMORY)`**.

During intensive 60 FPS mobile gaming (e.g., Genshin Impact, PUBG Mobile), a single uncompressed 1080p frame consumes ~8.3 MB of RAM. Allocating just 5–6 frame buffers will cause an instantaneous crash.

### CastSprint Zero-Copy Memory Rules
1. **Never Buffer Uncompressed Pixels**: `CVPixelBuffer` instances delivered by `processSampleBuffer(_:with:)` are passed immediately to the hardware `VTCompressionSession` on the delivery thread.
2. **Hardware Compression Pipeline**: `VideoToolbox` encodes frames directly in the GPU/Apple Silicon Media Engine.
3. **Bounded Network Queues**: Compressed packets are enqueued in a bounded ring buffer (maximum 8 compressed frames, total < 400 KB). If network congestion occurs, delta frames are dropped while IDR keyframes are preserved.
4. **Target Memory Footprint**: Under continuous 1080p 60 FPS streaming, CastSprint's broadcast extension consumes **< 18 MB of RAM**, safely beneath the 50 MB limit.

---

## 3. VideoToolbox Hardware H.264 / HEVC Encoding

Hardware encoding is managed via `VTCompressionSession`:

```swift
import VideoToolbox

final class VideoToolboxEncoder {
    private var session: VTCompressionSession?
    
    func setup(width: Int32, height: Int32, fps: Int32, bitrateBps: Int32) {
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else { return }
        
        // Low-latency configuration
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateBps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (fps * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
}
```

### Parameter Set Extraction (SPS / PPS)
When the first IDR frame or format description is produced, SPS and PPS NALUs are extracted from `CMFormatDescription` and dispatched as a CastSprint `VIDEO_CONFIG` message:

```swift
func extractSpsPps(from formatDescription: CMFormatDescription) -> Data? {
    var spsCount: size_t = 0
    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        formatDescription,
        parameterSetIndex: 0,
        parameterSetPointerOut: nil,
        parameterSetSizeOut: nil,
        parameterSetCountOut: &spsCount,
        nalUnitHeaderLengthOut: nil
    )
    
    var configData = Data()
    for index in 0..<spsCount {
        var pointer: UnsafePointer<UInt8>?
        var size: size_t = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: index,
            parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )
        if let pointer = pointer {
            // Prepend Annex-B start code (0x00000001)
            configData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            configData.append(pointer, count: size)
        }
    }
    return configData
}
```

---

## 4. Audio Capture & AAC Compression

ReplayKit delivers game audio via `processSampleBuffer(_:with: .audioApp)`.
- Internal audio is captured directly from the active game.
- The user can optionally disable microphone capture to ensure complete privacy.
- Audio samples are encoded to AAC-LC (48 kHz stereo, 128 kbps) using an `AudioConverterRef` hardware compressor and dispatched as `AUDIO_FRAME` packets.

---

## 5. Network Transport via Network.framework

CastSprint utilizes Apple's native `Network.framework` (`NWConnection`):
- Provides modern, asynchronous TLS 1.3 socket communication over Wi-Fi.
- Supports SHA-256 certificate fingerprint pinning matching the Windows or macOS receiver.
- Lowers kernel context-switching overhead compared to BSD sockets.
