# CastSprint macOS — CPU Performance Root Cause Analysis

## Executive Summary
A critical P0 CPU regression on macOS was observed where `CastSprint.app` consumed **~120.1% CPU**, spawned **73 threads**, and accumulated **264.5 MB of resident memory** immediately upon launch while completely idle, with no active screen mirroring session.

Following empirical diagnostic profiling using `/usr/bin/sample`, Activity Monitor, and `top`, the root cause was identified: an **infinite mutual recursion loop** within the device discovery delegate pattern coupled with unthrottled synchronous process execution that exhausted Grand Central Dispatch's worker thread pool.

---

## 1. Problem Identification & Initial Observation
- **Platform:** Apple Silicon (macOS 14+ / Darwin arm64)
- **Observed PID:** 92600 / 28324
- **Executable:** `/Applications/CastSprint.app/Contents/MacOS/CastSprintMac`
- **Initial Metrics:**
  - **CPU Utilization:** 120.1% – 121.7%
  - **Active Threads:** 73 threads
  - **Resident Memory:** 264.5 MB
  - **GPU Utilization:** 0% (indicating the CPU was not consumed by Metal shaders or GPU drawing)

---

## 2. Real Profiling Evidence: `/usr/bin/sample`
Executing `/usr/bin/sample <PID> 5` against the reproducing process captured 1,076 stack samples, exposing the exact smoking gun:

```text
Analysis of sampling CastSprintMac (pid 28324) every 1 millisecond
Call graph:
    1076 Thread_8842602   DispatchQueue_1: com.apple.main-thread  (serial)
    + 1076 start  (in dyld) + 6688  [0x19c5d7e80]
    +   1076 CastSprintMac_main  (in CastSprintMac) + 64  [0x100043a74]
    +     1076 static App.main()  (in SwiftUI) + 224  [0x1d57168b8]
    +       ...
    +       998 __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__  (in CoreFoundation) + 60
    +         998 _dispatch_main_queue_callback_4CF  (in libdispatch.dylib) + 944
    +           998 specialized closure #1 in USBDeviceManager.refreshDevices()  (in CastSprintMac) + 404

Dispatch Thread Soft Limit: 64 reached in 51 of 1076 samples -- too many dispatch threads blocked in synchronous operations
```

### Key Diagnostic Findings from the Trace:
1. **GCD Soft Limit Hit:** Grand Central Dispatch hit its hard/soft worker limit of **64 worker threads**. All 64 threads were blocked inside synchronous subprocess executions:
   `-[NSConcreteTask waitUntilExit]` -> `_NSReadFromFileDescriptorWithProgress` -> `read`.
2. **Main Thread Flooding:** Out of 1,076 samples, the main thread spent **998 samples (92.8%)** continuously executing dispatch blocks queued by `USBDeviceManager.refreshDevices()`.
3. **Continuous Cascade:** New blocks were being appended to dispatch queues faster than they could be retired.

---

## 3. Detailed Root Cause Breakdown

### Bug A: The Infinite Mutual Recursion Delegate Loop
In `MirroringCoordinator.swift`:
```swift
// Previous implementation:
public func refreshDevices() {
    usbManager.refreshDevices()
    adbManager.refreshDevices()
    ...
}

// Delegate callbacks:
public func adbDevicesDidChange(_ devices: [AndroidDevice]) {
    refreshDevices() // <-- Calls usbManager and adbManager again!
}

public func deviceManager(_ manager: USBDeviceManager, didUpdateDevices devices: [DiscoveredUSBDevice]) {
    refreshDevices() // <-- Calls usbManager and adbManager again!
}
```

When `MirroringCoordinator` called `refreshDevices()` at startup:
1. It called `usbManager.refreshDevices()` and `adbManager.refreshDevices()`.
2. When `usbManager.refreshDevices()` completed its AVFoundation discovery, it called its delegate:
   `delegate?.deviceManager(self, didUpdateDevices: updatedList)`.
3. `MirroringCoordinator.deviceManager(_:didUpdateDevices:)` responded by calling `self.refreshDevices()`.
4. `self.refreshDevices()` immediately reinvoked `usbManager.refreshDevices()` and `adbManager.refreshDevices()`.
5. Simultaneously, `adbManager.refreshDevices()` finished executing `adb devices -l` and notified its delegate:
   `delegate?.adbDevicesDidChange(parsed)`.
6. `MirroringCoordinator.adbDevicesDidChange` also responded by calling `self.refreshDevices()`.
7. This formed an exponential recursion loop, spawning dozens of scans per second.

### Bug B: Synchronous Subprocess Execution in a Polling Loop
In `ADBDeviceManager.swift`:
Each invocation of `refreshDevices()` spawned a separate macOS `Process()`:
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: command)
process.arguments = ["devices", "-l"]
process.run()
let data = pipe.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()
```
Because the recursion loop was firing continuously, hundreds of `adb devices -l` processes were spawned simultaneously. Each blocked a GCD worker thread waiting on pipe I/O and process exit, driving the thread count to 73 and pegging one CPU core at 100%+ in kernel/mach dispatch overhead.

### Bug C: Redundant SwiftUI Body Invalidation
Every iteration of the recursion loop assigned `self.availableDevices = unifiedList` on the `@Published` property of `MirroringCoordinator`. Even though the list contents were identical, SwiftUI treated the property modification as an invalidation signal, forcing repeated body re-evaluations across the entire UI hierarchy.

### Bug D: Unconditional Telemetry Loop
`MirroringCoordinator.init()` scheduled a 0.5s repeating `Timer` for latency and FPS telemetry regardless of whether mirroring was active, producing unnecessary periodic CPU wakeups when idle.

### Bug E: Duplicate NotificationCenter Observers
Both `MirroringCoordinator` and `USBDeviceManager` registered independent observers for `.AVCaptureDeviceWasConnected` and `.AVCaptureDeviceWasDisconnected`, triggering cascading double-refreshes whenever any device event occurred.

---

## 4. Source Files Modified & Architectural Remedies

| File | Changes Made |
| :--- | :--- |
| [`MirroringCoordinator.swift`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/App/MirroringCoordinator.swift) | • Decoupled scanning from list assembly: created `rebuildUnifiedDeviceList()`.<br>• Updated all delegate methods (`adbDevicesDidChange`, `didUpdateDevices`, `didDetectDeviceArrival`, `didDetectDeviceRemoval`) to call `rebuildUnifiedDeviceList()` instead of `refreshDevices()`.<br>• Added value deduplication before updating `@Published var availableDevices`.<br>• Removed duplicate NotificationCenter observers.<br>• Scoped `startTelemetryLoop()` strictly to `startMirroring()` and stopped it in `stopMirroring()`. |
| [`ADBDeviceManager.swift`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/Devices/ADBDeviceManager.swift) | • Replaced polling subprocess executions with **event-driven ADB socket tracking** using `NWConnection` to `127.0.0.1:5037` (`0012host:track-devices`).<br>• Socket streams device arrivals/removals asynchronously from the kernel with 0 CPU overhead when idle.<br>• Added concurrency gate `isScanning` and dedicated serial utility queue.<br>• Retained on-demand `devices -l` scan only for explicit manual user refreshes. |
| [`USBDeviceManager.swift`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/Devices/USBDeviceManager.swift) | • Offloaded `AVCaptureDevice.DiscoverySession` enumeration to background serial queue `com.castsprint.mac.usb.refresh`.<br>• Added `isRefreshing` concurrency gate to prevent re-entrant discovery.<br>• Added deduplication check (`if self.knownDevices != updatedList`) before notifying delegate. |
| [`UnifiedDevice.swift`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/Devices/UnifiedDevice.swift) | • Implemented comprehensive `Equatable` conformance comparing `id`, `name`, `status`, and `transport` to enable accurate deduplication. |
| [`MetalVideoRenderer.swift`](file:///Users/ta-shanto/Coding/products/CastSprint/apps/macos/CastSprintMac/Sources/CastSprintMac/Rendering/MetalVideoRenderer.swift) | • Added `CVMetalTextureCacheFlush(cache, 0)` in `clear()` to release GPU textures upon stream termination. |
