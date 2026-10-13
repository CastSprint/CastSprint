# Native iPhone USB Capture on macOS (No Companion App)

One of CastSprint’s most powerful capabilities is **native, driverless iPhone and iPad screen and audio mirroring over USB on macOS without installing any mobile application on the iOS device**.

This delivers tournament-grade latency (<15 ms), 60 FPS video, and uncompressed digital game audio with zero setup required on the player’s iPhone.

---

## 1. How It Works: Apple CoreMediaIO Screen Capture Subsystem

macOS includes a specialized subsystem within `CoreMediaIO.framework` designed for developer screen recording and testing (historically utilized by QuickTime Player and Xcode). When a trusted iOS device is plugged into a Mac via Lightning or USB-C, macOS establishes an internal multiplexed USB communication channel.

By default, iOS devices connected via USB are hidden from standard `AVCaptureDevice` enumeration until the `CoreMediaIO` screen capture provider property is activated.

### Enabling iOS Screen Capture Devices in Swift
To expose connected iPhones to `AVFoundation`, CastSprint sets the system-wide CoreMediaIO property:

```swift
import CoreMediaIO

func enableCoreMediaIOScreenCaptureDevices() {
    var prop = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOProviderPropertyAllowScreenCaptureDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var allow: UInt32 = 1
    let dataSize = UInt32(MemoryLayout<UInt32>.size)
    
    let result = CMIOObjectSetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &prop,
        0,
        nil,
        dataSize,
        &allow
    )
    
    if result != OSStatus(kCMIOBlockBufferNoErr) {
        NSLog("CastSprint: Failed to enable CMIO screen capture devices: %d", result)
    } else {
        NSLog("CastSprint: CMIO screen capture devices successfully enabled")
    }
}
```

Once this property is enabled, any USB-connected iPhone or iPad is immediately exposed as an `AVCaptureDevice` for both video and audio.

---

## 2. Device Discovery & Enumeration

Connected iPhones can be discovered using standard `AVCaptureDeviceDiscoverySession`:

```swift
import AVFoundation

func discoverConnectedIPhones() -> [AVCaptureDevice] {
    let discoverySession = AVCaptureDeviceDiscoverySession(
        deviceTypes: [.externalUnknown],
        mediaType: .video,
        position: .unspecified
    )
    
    return discoverySession?.devices.filter { device in
        // Filter for iOS devices by manufacturer / model ID
        device.manufacturer == "Apple Inc." &&
        (device.localizedName.contains("iPhone") || device.localizedName.contains("iPad"))
    } ?? []
}
```

### Trust Negotiation ("Trust This Computer")
For an iPhone to stream over USB:
1. The user must unlock their iPhone upon connecting the cable.
2. If prompted with **"Trust This Computer?"**, the user must tap **Trust** and enter their device passcode.
3. Once trusted, the device pairs with macOS `usbmuxd` and CoreMediaIO registers the audio/video endpoint.

---

## 3. High-Performance Media Pipeline

```
+-------------------------------------------------------------+
|  Physical iPhone (Running Mobile Game)                      |
+------------------------------+------------------------------+
                               | Lightning / USB-C
                               v
+-------------------------------------------------------------+
|  macOS CoreMediaIO / usbmuxd Multiplexed Transport          |
+------------------------------+------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|  CastSprint AVCaptureSession                                |
|  - AVCaptureDeviceInput (Video: iPhone Screen)              |
|  - AVCaptureDeviceInput (Audio: iPhone Digital Audio)       |
+---------------+-----------------------------+---------------+
                |                             |
                | Video CMSampleBuffer        | Audio CMSampleBuffer
                v                             v
+-------------------------------+   +-------------------------+
| AVCaptureVideoDataOutput      |   | AVCaptureAudioDataOutput|
| - kCVPixelFormatType_420Yp    |   | - Linear PCM 44.1/48kHz |
|   CbCr8BiPlanarVideoRange     |   |                         |
+---------------+---------------+   +------------+------------+
                |                                |
                v                                v
+-------------------------------+   +-------------------------+
| CVMetalTextureCache           |   | CoreAudio HAL Output    |
| - Zero-copy GPU Texture       |   | - Low-latency playback  |
+---------------+---------------+   +-------------------------+
                |
                v
+-------------------------------+
| Metal Gaming View / OBS Window|
+-------------------------------+
```

### Video Data Output Setup
```swift
let session = AVCaptureSession()
session.beginConfiguration()
session.sessionPreset = .high

guard let videoInput = try? AVCaptureDeviceInput(device: iPhoneDevice) else { return }
if session.canAddInput(videoInput) { session.addInput(videoInput) }

let videoOutput = AVCaptureVideoDataOutput()
videoOutput.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
]
videoOutput.alwaysDiscardsLateVideoFrames = true
videoOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)

if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
session.commitConfiguration()
session.startRunning()
```

### Zero-Copy Metal Presentation
Frames delivered by `captureOutput(_:didOutput:from:)` contain a native `CVPixelBuffer`.
CastSprint converts the `CVPixelBuffer` into Metal textures with **zero CPU-GPU memory copies** using `CVMetalTextureCache`:

```swift
var textureRef: CVMetalTexture?
let width = CVPixelBufferGetWidth(pixelBuffer)
let height = CVPixelBufferGetHeight(pixelBuffer)

CVMetalTextureCacheCreateTextureFromImage(
    kCFAllocatorDefault,
    metalTextureCache,
    pixelBuffer,
    nil,
    .r8Unorm, // Luma plane (Y)
    width,
    height,
    0,
    &textureRef
)
```

The Metal shader converts YUV (Bi-Planar NV12) to sRGB on the GPU in <0.5 ms, achieving the fastest possible rendering pipeline on Apple Silicon and Intel Macs.

---

## 4. Latency & Performance Profile

| Metric | Measured Value | Comparison (Standard AirPlay) |
|:---|:---:|:---:|
| **Glass-to-Glass Latency** | **12 – 18 ms** | 70 – 120 ms |
| **Frame Rate** | 60.0 FPS locked | 30 – 60 FPS variable |
| **Resolution** | Native Device Retina | Compressed 1080p |
| **CPU Usage (M1/M2/M3)** | < 0.8% | > 8.0% |
| **Audio Latency** | < 10 ms | > 100 ms |

---

## 5. OBS Studio Integration on macOS

1. In OBS Studio for macOS, add a **Window Capture** source.
2. Select `[CastSprint]: CastSprint — Gaming View`.
3. Set Window Capture mode to standard **ScreenCaptureKit Window Capture**.
4. Audio is routed through macOS default audio output or isolated via a virtual audio device (BlackHole) with zero latency.
