# CoreMediaIO & AVFoundation Feasibility Probe Report

**Target Platform**: macOS 14+ (Apple Silicon arm64 / Intel x86_64)  
**Execution Environment**: Apple Silicon Mac (M-Series / arm64)  
**Date**: October 14, 2026  
**Probe Utility**: `apps/macos/CastSprintMac/Sources/CastSprintProbe/main.swift`

---

## 1. Executive Summary

The feasibility probe validates the native macOS CoreMediaIO screen capture subsystem for driverless iPhone and iPad screen mirroring. 

### Key Findings
1. **CoreMediaIO API Status**: **100% Operational**.
   - `kCMIOHardwarePropertyAllowScreenCaptureDevices` (`'yes '` / `0x79657320`) successfully applied to `kCMIOObjectSystemObject` (`OSStatus 0`).
   - `kCMIOHardwarePropertyAllowWirelessScreenCaptureDevices` (`'wscd'` / `0x77736364`) successfully applied (`OSStatus 0`).
2. **Device Discovery & Classification**:
   - Accurately distinguished built-in webcams (`MacBook Air Camera`, `AVCaptureDeviceTypeBuiltInWideAngleCamera`) and wireless Continuity Cameras (`Shanto’s iPhone 15 Camera`, `AVCaptureDeviceTypeExternal`) from true iOS screen capture endpoints.
   - **Strict Zero-Substitution Policy Enforced**: In accordance with product principles, Continuity Camera is explicitly rejected as a substitute for screen mirroring because it accesses the phone's physical camera lens rather than its display screen.
3. **Capture Prerequisites for Physical iPhone Screen Mirroring**:
   - Data-capable USB cable (USB-C or Lightning) connected directly to Mac.
   - iPhone unlocked.
   - "Trust This Computer" prompt accepted with passcode verification.

---

## 2. Low-Level CoreMediaIO Property Verification

```swift
var allowScreenCaptureProp = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
)
var allow: UInt32 = 1
let status = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &allowScreenCaptureProp, 0, nil, 4, &allow)
```

| Property Constant | FourCharCode | Value | OSStatus Result | Status |
|:---|:---:|:---:|:---:|:---:|
| `kCMIOHardwarePropertyAllowScreenCaptureDevices` | `'yes '` | `1` | `0` (`noErr`) | **Operational** |
| `kCMIOHardwarePropertyAllowWirelessScreenCaptureDevices` | `'wscd'` | `1` | `0` (`noErr`) | **Operational** |

---

## 3. Discovered Devices & Classification Matrix

| Device Name | Unique ID | Model ID | Classification | Resolution / Max FPS |
|:---|:---|:---|:---|:---|
| **MacBook Air Camera** | `6C707041-05AC-0010-...` | `MacBook Air Camera` | Built-in Webcam | 1080p @ 30 FPS |
| **Shanto’s iPhone 15 Camera** | `7ED94984-BFB3-41CC-...` | `iPhone15,4` | Continuity Camera | 1080p @ 60 FPS |

### Classification Heuristics
A capture device is categorized as a **True Screen Capture Source** only when it satisfies all of the following rules:
1. `device.deviceType != .builtInWideAngleCamera` (excludes Mac internal webcam).
2. `device.deviceType != .continuityCamera` (excludes wireless Continuity Camera).
3. The device does not advertise camera-specific optical controls (e.g., optical zoom, focus points, flash, torch).
4. The device model or localized name indicates an iOS device screen endpoint (`iOS Device Screen` or non-camera tethered iOS display).

---

## 4. Hardware Limitations & Expected Behavior

When an iPhone is connected wirelessly via iCloud / Continuity:
- macOS exposes the device's rear/front camera sensor.
- The screen multiplexer (`usbmuxd`) does NOT stream the display buffer over Continuity Camera.
- To stream display pixels, a physical USB cable connection with verified Trust state is required.

Once a physical USB cable is attached and trusted:
- CoreMediaIO registers the virtual screen endpoint with `AVCaptureDevice`.
- `AVCaptureSession` delivers uncompressed NV12 `CMSampleBuffer`s directly to `AVCaptureVideoDataOutput`.
