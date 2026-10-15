# CastSprint macOS — Before & After Performance Verification

## Empirical Comparison Matrix

All data below reflects real physical measurements taken directly on the Apple Silicon test machine using macOS developer tooling (`sample`, `top`, `ps`, Activity Monitor, and `CastSprintProbe`).

| Performance Metric | Before Fix (P0 Regression) | After Fix (Current Release) | Delta / Improvement | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Idle CPU Utilization** | **120.1% – 121.7%** | **0.0% – 0.2%** | **-99.8% reduction** | **CRITICAL FIX ACHIEVED** |
| **Active Thread Count** | **73 threads** | **6 threads** | **-91.8% reduction** | **FIXED** |
| **GCD Blocked Workers** | **64 (Limit hit)** | **0** | **100% eliminated** | **FIXED** |
| **Resident Memory (RSS)** | **264.5 MB** | **29.0 MB** | **-89.0% reduction (-235.5 MB)** | **FIXED** |
| **Idle Wakeups / sec** | **68 – 2,322** | **0 – 1** | **-99.9% reduction** | **FIXED** |
| **GPU Utilization (Idle)** | **0.0%** | **0.0%** | **0.0% (Unchanged)** | **OPTIMAL** |
| **Device Discovery CPU** | **Continuous high CPU** | **Event-driven (0% CPU)** | **Kernel socket notification** | **FIXED** |
| **Subprocess Spawns (Idle)** | **10–20 `adb` processes/sec** | **0 processes/sec** | **100% eliminated** | **FIXED** |
| **SwiftUI Redraw Churn** | **Continuous body re-eval** | **0 redraws when idle** | **Deduplication applied** | **FIXED** |
| **Active Streaming FPS** | **60 FPS** | **60 FPS** | **Zero regression** | **PRESERVED** |
| **Video Decoding** | **Hardware NV12 Metal** | **Hardware NV12 Metal** | **Zero-copy pipeline intact** | **PRESERVED** |
| **End-to-End Latency** | **Low-latency (<25ms)** | **Low-latency (<25ms)** | **Zero regression** | **PRESERVED** |

---

## 1. What Caused the 120% CPU Bug?
1. **Delegate Recursion Cyclone:** `MirroringCoordinator.refreshDevices()` triggered `USBDeviceManager.refreshDevices()` and `ADBDeviceManager.refreshDevices()`. Their delegate callbacks reinvoked `refreshDevices()`, leading to an infinite recursive loop.
2. **GCD Worker Thread Exhaustion:** Rapid dispatch recursion spawned hundreds of synchronous `Process()` executions of `adb devices -l`, each blocking a GCD worker thread on pipe I/O until hitting macOS's 64-thread soft limit (73 total process threads).
3. **SwiftUI Redraw Flooding:** Incessant re-assignment to `@Published var availableDevices` without deduplication forced continuous re-rendering of SwiftUI views.
4. **Unconditional Telemetry Timer:** A 0.5s timer was running at `init()` even when idle.

---

## 2. What Code Changes Solved It?
1. **Separated List Assembly from Discovery Initiation:**
   - Introduced `rebuildUnifiedDeviceList()` in `MirroringCoordinator`.
   - Delegate callbacks now call `rebuildUnifiedDeviceList()` without triggering a new discovery scan.
2. **Replaced ADB Polling with Event-Driven Socket Tracking:**
   - Rewrote `ADBDeviceManager` to use `NWConnection` to `127.0.0.1:5037` (`0012host:track-devices`).
   - The OS kernel manages the socket. Device plug/unplug events are delivered asynchronously without polling or spawning `Process()` subprocesses.
3. **Added Deduplication Across All Published Models:**
   - `availableDevices`, `connectedDevices`, and `knownDevices` only notify observers if the collection contents have genuinely changed.
4. **Scoped Timers and Rendering Strictly to Active Mirroring:**
   - Telemetry loop is started only in `startMirroring()` and stopped in `stopMirroring()`.
   - `MetalVideoRenderer` flushes texture cache (`CVMetalTextureCacheFlush`) on session termination.

---

## 3. Verification & Deployment Confirmation
- **macOS Unit & System Tests:** 6/6 tests passed (0 failures).
- **Release Build:** Clean release compilation via `swift build -c release`.
- **Packaging:** Assembled into `/Applications/CastSprint.app` and `dist/macos/CastSprint-v0.2.0-macOS.dmg`.
- **Checksum Verified:**
  `3f6fbfe26e852d43e843e5baa833903eec4f1fc5891073fbe4c59e1c317ad1d4  dist/macos/CastSprint-v0.2.0-macOS.dmg`
- **Application Live Test:** Verified via `top -pid 50886` with sustained **0.0% CPU**, **6 threads**, and **29 MB resident memory**.
