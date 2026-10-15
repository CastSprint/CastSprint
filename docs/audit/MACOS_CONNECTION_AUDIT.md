# CastSprint macOS — Technical Connection Audit

## 1. iPhone USB Direct Capture (Zero Mobile App)

### Technical Architecture
The macOS iPhone USB screen mirroring architecture operates directly via the Apple **CoreMediaIO** and **AVFoundation** subsystems. When an iOS device is connected over USB to a Mac:
1. `CMIOManager.shared.enableScreenCaptureDevices()` configures the system property `kCMIOHardwarePropertyAllowScreenCaptureDevices`.
2. The macOS USB multiplexer driver recognizes the trusted device and exposes a virtual AVFoundation camera device with device types `.external` and `.continuityCamera`.
3. CastSprint's `USBDeviceManager` inspects all discovered devices. Crucially, it differentiates between:
   - **Continuity Camera (Webcam Feed):** Wireless or wired camera lens feed. This is strictly filtered and flagged as `.needsTrust` or `.unauthorized` so that webcam video is never presented as gameplay screen capture.
   - **True Screen Capture Source:** Uncompressed direct screen capture stream matching device unique IDs registered via CoreMediaIO.
4. `IPhoneUSBCaptureSession` binds an `AVCaptureVideoDataOutput` requesting `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (NV12).
5. As `CMSampleBuffer` frames arrive, `CMSampleBufferGetImageBuffer` extracts the `CVPixelBuffer` and delivers it directly to `MetalVideoRenderer` via `CVMetalTextureCacheCreateTextureFromImage`, providing **zero CPU copy** presentation directly on Apple Silicon GPUs.

---

## 2. CastSprint iOS Wireless Mirroring (ScreenCaptureKit / ReplayKit)

### Technical Architecture
For wireless iPhone streaming:
1. The companion CastSprint iOS application utilizes a ReplayKit Broadcast Extension (`LegacyBroadcastExtension`) or ScreenCaptureKit system capture.
2. The user initiates broadcasting from Control Center or the CastSprint iOS app.
3. Frames are passed directly into a VideoToolbox hardware encoder on iOS (`VTCompressionSession`), producing an H.264 Annex-B NALU bitstream.
4. Audio buffers are captured via `AudioPlaybackCapture` on iOS and packetized with microsecond PTS timestamps.
5. The iOS app discovers the Mac using Bonjour mDNS (`_castsprint._tcp.local.`) and connects over TCP port 27183.
6. The Mac verifies the 4-digit pairing PIN, accepts the stream, feeds NALUs into `VideoToolboxDecoder` (`VTDecompressionSession`), and renders them via Metal.

---

## 3. Apple AirPlay (System Mode vs. Custom Receiver)

### Technical Comparison
| Attribute | macOS System AirPlay Receiver | macOS iPhone Mirroring (macOS 15) | CastSprint Native iOS Streaming | Custom Third-Party Receiver |
| :--- | :--- | :--- | :--- | :--- |
| **Availability** | macOS Monterey (12.0+) | macOS Sequoia (15.0+) | Any macOS 12.0+ Mac | Experimental |
| **Mobile App** | Not Required | Not Required | Required (CastSprint iOS) | Not Required |
| **Target Latency** | 80–150 ms (Jitter buffered) | 50–100 ms | **15–25 ms (Low-latency)** | 80–120 ms |
| **Gaming Suitability**| Casual / Presentation | Interactive UI container | **Competitive 60 FPS Gaming**| Variable |
| **OBS Capture** | Window Capture | Window Capture | **Direct Native OBS Viewport** | Complex |
| **Framerate** | Variable 30–60 FPS | Dynamic | **Locked 60 FPS** | Variable |

### Guidance & ScreenCaptureKit Bridge Investigation
- **System AirPlay Mode:** CastSprint provides direct guided setup opening `System Settings -> General -> AirDrop & Handoff -> AirPlay Receiver`.
- **ScreenCaptureKit Window Bridge:** While ScreenCaptureKit can capture visible AppKit windows on macOS, capturing the system AirPlay Receiver window introduces unnecessary latency and fails when FairPlay/DRM flags are active. Therefore, CastSprint recommends native USB or CastSprint LAN streaming for gaming, and offers System AirPlay as a companion presentation mode.

---

## 4. Android USB via ADB Reverse Proxy

### Technical Architecture
1. `ADBDeviceManager` establishes a non-blocking TCP socket to `127.0.0.1:5037` executing `0012host:track-devices`.
2. When an Android device with USB Debugging is plugged in, the ADB daemon transmits device status without invoking polling subprocesses.
3. Upon connection, CastSprint executes:
   `adb -s <serial> reverse tcp:27183 tcp:27183`
4. The CastSprint Android application is launched automatically (`am start -n com.castsprint.android/.MainActivity`).
5. The Android app connects to `localhost:27183` through the ADB reverse proxy, streaming H.264 video and internal game audio over the physical USB data cable.

---

## 5. Android Wireless ADB & Wi-Fi Hotspot

### Technical Architecture
- **Wireless ADB:** Supported on Android 11+ via official Wi-Fi pairing (`adb pair <host>:<port> <code>`) and connection (`adb connect <host>:<port>`). Once connected over TCP, the reverse tunnel functions identically to wired USB ADB.
- **Wi-Fi Hotspot:** When the Mac joins the Android device's Wi-Fi Hotspot, traffic routes directly to the default gateway (typically `192.168.43.1:27183`). CastSprint's Bonjour advertiser and TCP listener bind to `0.0.0.0:27183`, automatically accepting streams from the hotspot subnet without any internet access or cloud relay.
