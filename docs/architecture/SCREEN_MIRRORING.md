# CastSprint — Display Screen Mirroring Architecture

## 1. Core Architecture Principles
1. **Physical Phone Gameplay**: The user plays mobile games (e.g. PUBG Mobile, Free Fire, Call of Duty Mobile) directly on the physical phone touchscreen with the phone unlocked.
2. **Zero Camera Sensor**: No front, rear, or Continuity Camera feeds are ever captured or presented as gameplay.
3. **Hardware-Accelerated Zero-Copy Presentation**: Metal on macOS, Direct3D 11 on Windows, and hardware-accelerated rendering on Linux.
4. **Lowest Practical Latency**: Bounded frame queues, zero redundant transcoding on native USB paths, and hardware encoding/decoding.

---

## 2. Platform Pipelines

### 2.1 iPhone ➔ macOS Native USB Display Pipeline
```
+-----------------------------------------------------------+
| Unlocked Physical iPhone 15 Running Touchscreen Gameplay   |
+-----------------------------------------------------------+
                             |
                   USB-C / Lightning Cable
                             |
+-----------------------------------------------------------+
| Apple CoreMediaIO DAL Subsystem                           |
| (kCMIOHardwarePropertyAllowScreenCaptureDevices = 1)      |
+-----------------------------------------------------------+
                             |
+-----------------------------------------------------------+
| CastSprint IPhoneUSBCaptureSession                        |
| - AVCaptureSession (locked to 1080p60)                    |
| - AVCaptureVideoDataOutput (NV12 420v planar)             |
+-----------------------------------------------------------+
                             | CMSampleBuffer / CVPixelBuffer
                             v
+-----------------------------------------------------------+
| CastSprint MetalVideoRenderer                             |
| - CAMetalLayer / MTKView                                  |
| - Embedded BT.709 YUV Fragment Shader                     |
| - Zero-Copy GPU Texture Binding                           |
+-----------------------------------------------------------+
                             |
                             v
+-----------------------------------------------------------+
| CastSprint Gameplay View ➔ OBS Studio Window Capture      |
+-----------------------------------------------------------+
```

### 2.2 Android ➔ Desktop (USB & Wi-Fi) Pipeline
```
+-----------------------------------------------------------+
| Android Smartphone Running Game                           |
+-----------------------------------------------------------+
                             |
+-----------------------------------------------------------+
| ScreenCaptureService (Foreground Service)                 |
| - MediaProjection ➔ VirtualDisplay                        |
| - MediaCodec Surface Hardware Encoder (H.264 Baseline/HP) |
+-----------------------------------------------------------+
                             | Protocol V1 Video Packets
                   USB (ADB) or Local Wi-Fi
                             |
+-----------------------------------------------------------+
| Desktop Receiver (macOS / Windows / Linux)                |
| - NetworkStreamReceiver / LanServer (Port 27183)          |
| - Hardware Decoder (VideoToolbox / Media Foundation / VA) |
| - Native GPU Renderer (Metal / D3D11 / Linux)             |
+-----------------------------------------------------------+
```
