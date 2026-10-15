# macOS Crash Root Cause Analysis & Resolution

## Incident Overview
- **Incident Dates/Times:** 2026-10-15 08:48:04, 09:04:08, 09:04:54
- **Process:** `CastSprintMac` (Bundle ID: `com.castsprint.macos`)
- **Environment:** macOS 27.0 (Apple Silicon, arm64e), iPhone 15 (iOS 18+ over USB-C)
- **Status:** **RESOLVED & VERIFIED**

---

## 1. Primary Crash: `SIGABRT` in `CoreAudioOutput.playSampleBuffer(_:)`

### Stack Trace
```text
Exception: EXC_CRASH (SIGABRT)
libsystem_c.dylib : abort
libc++abi.dylib : __abort_message
libobjc.A.dylib : objc_exception_throw
CoreFoundation : +[NSException raise:format:]
AVFAudio : -[AVAudioPlayerNode scheduleBuffer:atTime:options:completionCallbackType:completionHandler:]
AVFAudio : -[AVAudioPlayerNode scheduleBuffer:atTime:options:completionHandler:]
CastSprintMac : CoreAudioOutput.playSampleBuffer(_:)
CastSprintMac : MirroringCoordinator.captureSession(_:didOutputAudio:)
CastSprintMac : specialized IPhoneUSBCaptureSession.captureOutput(_:didOutput:from:)
AVFCapture : __56-[AVCaptureAudioDataOutput_Tundra _render:sampleBuffer:]_block_invoke
```

### Root Cause
When an iPhone is connected via USB cable, CoreMediaIO exposes its digital audio stream as a mono (1 channel), 48,000 Hz, 32-bit floating-point stream (`kAudioFormatLinearPCM`).
In `CoreAudioOutput.swift`, `AVAudioEngine` had connected `playerNode` to `mainMixerNode` using the mixer's hardware format (2 channels, 44,100 Hz / 48,000 Hz stereo).
When the first audio packet was delivered, `playerNode.scheduleBuffer(pcmBuffer)` was called directly with the mono 1-channel buffer. `AVAudioPlayerNode` requires that any scheduled buffer strictly matches the node's output format. When they mismatched, `AVAudioPlayerNode` threw an Objective-C `NSException` (`com.apple.coreaudio.avfaudio`), causing an immediate `SIGABRT` termination.

### Resolution
1. Rewrote `CoreAudioOutput.swift` to introduce an `AVAudioConverter` pipeline.
2. In `playSampleBuffer(_:)`, incoming `AudioBufferList` is extracted safely with `CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer`.
3. The buffer is converted from the incoming format (e.g. 1 ch 48 kHz mono) into the engine's canonical stereo format.
4. Added an explicit validation check (`outPCM.format == playerNode.outputFormat(forBus: 0)`) before invoking `scheduleBuffer`.
5. Handled `AVAudioEngineConfigurationChange` notifications to recover automatically if system audio devices or headphones change.

---

## 2. Secondary Bug: Faulty Device Classification as "Continuity Camera"

### Problem
macOS AVFoundation labels the USB-connected iPhone video source as `"Shanto’s iPhone 15 Camera"` with device type `.external`.
The previous code in `USBDeviceManager.swift` contained:
```swift
let isContinuity = (dev.deviceType == .continuityCamera) ||
                   (dev.localizedName.contains("Camera") && dev.modelID.contains("iPhone"))
```
Because the name contains `"Camera"` and the model contains `"iPhone"`, it falsely classified the real USB screen as Continuity Camera, set its status to `Busy`, and prevented screen mirroring.

### Resolution
1. Corrected `isContinuity` to only match true Continuity devices (`dev.deviceType == .continuityCamera || dev.localizedName.contains("Continuity")`).
2. Cleaned display name by stripping the `" Camera"` suffix (e.g. displaying `"Shanto’s iPhone 15"`).
3. Marked `isTrueScreenCapture = true` and `state = .ready`.

---

## 3. Protocol Test Simulator Removal from Normal Workflows

### Resolution
Wrapped `Protocol Test Simulator` under `#if DEBUG` in `MirroringCoordinator.swift`. In release builds, only real physical devices are shown, eliminating user confusion and preventing synthetic feeds from masquerading as real connections.
