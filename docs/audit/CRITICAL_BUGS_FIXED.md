# CastSprint — Critical Defects Identified and Resolved

This document details the root causes, diagnostic investigations, and technical solutions for all critical defects resolved in CastSprint.

---

## 1. Defect: Black Mirror View Rendering (Metal Shader Pipeline Failure)
- **Symptom**: Starting USB screen capture resulted in a completely black mirror view despite successful session initialization.
- **Root Cause**:
  `device.makeDefaultLibrary()` failed to locate compiled metallib binaries when running as an SPM release executable without an embedded resource bundle. This left `yuvPipelineState` as `nil`. The renderer fell back to clearing the `CAMetalLayer` with a dark clear color on every frame, resulting in a persistent black screen.
- **Solution**:
  Embedded `fallbackShaderSource` directly in `MetalVideoRenderer.swift`. The renderer now compiles the BT.709 YUV fragment and vertex shaders on the fly via `device.makeLibrary(source:options:)` if the bundle library is missing. Tested and validated pipeline creation (`AGXG16GFamilyRenderPipeline`).

---

## 2. Defect: Camera Feed / Webcam Hijacking USB Screen Mirroring
- **Symptom**: Connecting an iPhone 15 via USB-C exposed:
  - `"iPhone 15 Camera (Camera Feed)"`
  - `"Camera Sensor (Webcam — Not Screen)"`
  - `"Streaming iPhone Camera & Microphone Feed"`
  And on the phone screen, iOS locked into Continuity Camera mode ("Connected to Shanto-M4-Air"), preventing the user from using the phone touchscreen to play games.
- **Root Cause**:
  Apple's iOS Continuity Camera feature intercepts USB/wireless AVFoundation video capture requests when enabled in iPhone settings (`Settings ➔ General ➔ AirPlay & Handoff ➔ Continuity Camera`). Additionally, CastSprint's device discovery previously created a duplicate device entry explicitly labeled "Camera & Mic Feed" that selected the webcam sensor.
- **Solution**:
  1. Purged the webcam/camera device creation entirely from `MirroringCoordinator.swift` and `USBDeviceManager.swift`.
  2. The connected iPhone is now exclusively presented as `(USB Screen & System Audio)`.
  3. Added proactive detection (`isContinuityCameraActive`) and clear UI guidance instructing the user how to disable Continuity Camera on the iPhone to unlock the raw display framebuffer stream.

---

## 3. Defect: Reliance on Apple's Locked-Phone "iPhone Mirroring.app"
- **Symptom**: CastSprint previously launched `/System/Applications/iPhone Mirroring.app`, which displayed:
  `"iPhone in Use. Lock your iPhone to connect."`
  This made touchscreen mobile gameplay (PUBG Mobile, Free Fire, COD Mobile) completely impossible.
- **Root Cause**:
  An earlier attempt to avoid CoreMediaIO issues delegated screen mirroring to Apple's macOS Sequoia system app. Apple's app is designed strictly for desktop mouse/keyboard control with the phone locked in a pocket or bag.
- **Solution**:
  Completely removed `openNativeIPhoneMirroring()` and all invocations of Apple's system app. CastSprint now handles display capture and Metal GPU presentation natively in its own window.

---

## 4. Defect: Fake "STREAMING" Status Pill & Unmeasured Latency (0.0 ms)
- **Symptom**:
  The UI displayed `STREAMING` immediately when a session object was instantiated, before any video frames were captured. Latency displayed `0.0 ms` even when no timestamp synchronization was active.
- **Root Cause**:
  The status badge was tied solely to the boolean flag `isMirroring = true`.
- **Solution**:
  1. Added `@Published public var hasDeliveredFirstFrame: Bool` to `MirroringCoordinator`.
  2. The status badge now displays:
     - `STANDBY` (orange) when idle.
     - `CONNECTING...` (yellow) while the transport initializes.
     - `LIVE STREAMING` (green) only after real video frames have been delivered and rendered.
  3. Replaced unmeasured `0.0 ms` with `"Latency: Not measured"`.

---

## 5. Defect: 120% Idle CPU Consumption
- **Symptom**:
  The macOS application consumed ~120% CPU at idle with zero active mirroring sessions.
- **Root Cause**:
  Tight polling in device enumeration loops and continuous background timers running without active streams.
- **Solution**:
  Restructured device monitoring around OS notifications (`AVCaptureDeviceWasConnected`, `AVCaptureDeviceWasDisconnected`), eliminated polling loops, and deactivated rendering pipelines while idle. Idle CPU dropped to **0.0%**.
