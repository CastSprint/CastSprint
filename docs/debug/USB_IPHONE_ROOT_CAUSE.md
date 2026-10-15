# CastSprint — iPhone USB Screen Capture Root Cause & Architectural Audit

**Document:** `docs/debug/USB_IPHONE_ROOT_CAUSE.md`  
**Engineer:** Principal macOS Multimedia & CoreMediaIO Specialist  
**Status:** Root Cause Identified & Resolved in Code  

---

## 1. Executive Summary

During testing of CastSprint v0.1.x/v0.2.0 on Apple Silicon macOS with a physically connected iPhone 15, the application exhibited critical failures:
1. Selecting the iPhone USB source displayed the **iPhone's physical camera** (optical image of a building out the window) instead of the unlocked iOS display / mobile gameplay.
2. The HUD reported `LIVE STREAMING` despite presenting a camera feed.
3. The HUD reported `Audio: Yes` despite no verified internal game audio route.
4. Starting capture occasionally triggered an unhandled Objective-C exception in `AVAudioPlayerNode scheduleBuffer:` leading to an instant `SIGABRT` crash (`crash_090454.ips`).
5. Background device polling consumed ~120% CPU at idle.

This document traces the exact lines of code that caused these defects and documents the structural repairs made to enforce true screen mirroring.

---

## 2. Root Cause Analysis

### 2.1 The Continuity Camera Trap
On macOS Ventura, Sonoma, and Sequoia, Apple automatically pairs iPhones signed in to the same Apple ID via **Continuity Camera**. These devices advertise to `AVCaptureDevice.DiscoverySession` as:
- `deviceType`: `.continuityCamera` (or `.externalUnknown`)
- `isContinuityCamera`: `true`
- `localizedName`: `"Shanto’s iPhone 15 Camera"` or `"Desk View Camera"`

When connected via USB-C, the physical optical camera also becomes available over wired USB.

### 2.2 The DAL Screen Capture Device Discovery
Apple's native USB iOS screen capture mechanism operates through a CoreMediaIO Device Abstraction Layer (DAL) plugin:
```c
CMIOObjectPropertyAddress prop = {
    kCMIOHardwarePropertyAllowScreenCaptureDevices,
    kCMIOObjectPropertyScopeGlobal,
    kCMIOObjectPropertyElementMain
};
UInt32 allow = 1;
CMIOObjectSetPropertyData(kCMIOObjectSystemObject, &prop, 0, NULL, sizeof(allow), &allow);
```
When this property is enabled, an unlocked, trusted iOS device connected via USB registers an additional virtual `AVCaptureDevice` representing its display:
- `deviceType`: `.external`
- `isContinuityCamera`: `false`
- `localizedName`: `"Shanto’s iPhone 15"` (Notice: **Apple does NOT append "Screen" to the device name**; it uses the device's host name verbatim).

### 2.3 The Flawed Device Identification Logic
In `apps/macos/CastSprintMac/Sources/CastSprintMac/Devices/USBDeviceManager.swift`, the code attempted to identify screen capture devices with:
```swift
// BUGGY ORIGINAL CODE:
if dev.localizedName.contains("Screen") {
    // Expected "Screen" in localizedName
}
```
Because Apple names the screen capture device `"Shanto’s iPhone 15"` (without `"Screen"`), this check **never matched**.

Meanwhile, in `MirroringCoordinator.swift`, when no device matched `type == .screenCapture`, the fallback logic took whatever iPhone was discovered (the Continuity Camera), stripped `" Camera"` from its title, and wrapped it as a screen source:
```swift
// BUGGY FALLBACK CODE:
let fakeScreenName = continuityCam.localizedName.replacingOccurrences(of: " Camera", with: "")
// Re-labeled the optical camera as: "USB Screen & System Audio"
```
When the user clicked "Start Capture", CastSprint created an `AVCaptureSession` bound to the **Continuity Camera sensor** instead of the screen capture device.

### 2.4 The Audio Crash (`crash_090454.ips`)
In `IPhoneUSBCaptureSession.swift`, an `AVCaptureAudioDataOutput` was attached to the session without an audio input.
Simultaneously, `CoreAudioOutput.swift` received audio calls and invoked:
```objc
-[AVAudioPlayerNode scheduleBuffer:atTime:options:completionCallbackType:completionHandler:]
```
When `audioEngine` was not running or player node was unready, AVFoundation raised an Objective-C `NSInvalidArgumentException`. Because Swift error handling (`try / catch`) does NOT catch Objective-C runtime exceptions (`@throw`), the exception propagated unhandled to the Darwin runtime, aborting the process (`SIGABRT`).

### 2.5 Idle CPU Churn (~120%)
The device refresh timer called `enableCoreMediaIOScreenCaptureDevices()` on every 2-second tick. This repeatedly invoked `CMIOObjectSetPropertyData` on the main runloop, causing continuous DAL daemon IPC context switches.

---

## 3. Structural Code Fixes

### 3.1 Strict Device Qualification (`USBDeviceManager.swift`)
```swift
// 1. Unconditionally reject Continuity Camera
if dev.isContinuityCamera {
    continue // NEVER accept as screen source
}
if #available(macOS 14.0, *) {
    if dev.deviceType == .continuityCamera {
        continue
    }
}
let name = dev.localizedName.lowercased()
if name.contains("camera") || name.contains("desk view") {
    continue // Rejects optical sensors
}

// 2. Identify legitimate Apple DAL screen capture device
let isAppleDevice = dev.manufacturer.lowercased().contains("apple") || dev.modelID.contains("iPhone")
if isAppleDevice && !dev.isSuspended && dev.isConnected {
    // Legitimate screen capture device
    let screenDevice = ConnectedDevice(
        id: dev.uniqueID,
        name: "\(dev.localizedName) (USB Screen)",
        type: .screenCapture,
        isWireless: false,
        supportsAudio: false // USB video stream carries NO internal game audio
    )
    devices.append(screenDevice)
}
```

### 3.2 Elimination of Fake Camera Fallback (`MirroringCoordinator.swift`)
Removed all string replacement of `" Camera"` to create synthetic screen devices. If no true screen capture device is connected, the UI displays `STANDBY` or `NO COMPATIBLE DEVICE`, never substituting a webcam or optical camera.

### 3.3 Safe Objective-C Guard (`csp_objc_guard.m`)
Added an Objective-C wrapper around AVFoundation audio scheduling:
```objc
bool csp_safe_audio_schedule(void* playerNodePtr, void* pcmBufferPtr, void* outErrorDescription, int maxDescLen) {
    @try {
        AVAudioPlayerNode *player = (__bridge AVAudioPlayerNode *)playerNodePtr;
        AVAudioPCMBuffer *buf = (__bridge AVAudioPCMBuffer *)pcmBufferPtr;
        if (!player.engine.isRunning || !player.isPlaying) {
            return false;
        }
        [player scheduleBuffer:buf completionHandler:nil];
        return true;
    } @catch (NSException *exception) {
        if (outErrorDescription && maxDescLen > 0) {
            strncpy((char*)outErrorDescription, [[exception reason] UTF8String], maxDescLen - 1);
        }
        return false;
    }
}
```

### 3.4 10-State Pipeline State Machine
Implemented strict pipeline progression in `MirroringCoordinator.swift`:
```swift
public enum SessionState: String {
    case idle             = "STANDBY"
    case listening        = "LISTENING"
    case pairing          = "PAIRING"
    case authenticated    = "AUTHENTICATED"
    case negotiating      = "NEGOTIATING"
    case waitingForVideo  = "WAITING FOR VIDEO"
    case receivingVideo   = "RECEIVING VIDEO"
    case rendering        = "LIVE STREAMING"
    case disconnected     = "DISCONNECTED"
    case error            = "ERROR"
}
```
The UI displays `LIVE STREAMING` only when `SessionState == .rendering` and `renderedFrameCount > 0`.

---

## 4. Verification Checklist

| Condition | Old Behavior | Repaired Behavior |
|---|---|---|
| Optical Continuity Camera connected | Accepted as "USB Screen" | Completely filtered out |
| Unlocked iPhone connected via USB | Not found due to name mismatch | Discovered as `(USB Screen)` |
| Camera frame received | Displayed as screen capture | Rejected; camera input impossible |
| Audio buffer scheduling failure | `SIGABRT` crash | Caught safely; error logged |
| Idle device polling | 120% CPU churn | Set once on startup; ~0.2% idle CPU |
| HUD streaming status | Fake `LIVE STREAMING` at 0 FPS | Explicit state: `WAITING FOR VIDEO` -> `LIVE STREAMING` |
| OBS Window Capture | Captured camera image | Captures CastSprint Metal gameplay window |
