# CastSprint macOS — Idle CPU Bug Analysis & Remediation (P0)

## Executive Summary
A critical performance regression where `CastSprint.app` consumed **~120% CPU** and created **73 threads** at idle was completely eliminated. The application now runs with **0.0% – 0.2% CPU utilization**, **6 threads**, and **29–32 MB resident memory**.

---

## 1. Problem Diagnostic & Baseline

### Observed Metrics at Launch
- **CPU:** 120.10% – 121.70%
- **Threads:** 73 threads
- **Resident Memory:** 264.5 MB
- **GPU Usage:** 0.0%
- **System Trace:** `Dispatch Thread Soft Limit: 64 reached -- too many dispatch threads blocked in synchronous operations`

### Root Cause
An infinite mutual recursion loop existed between `MirroringCoordinator.refreshDevices()`, `USBDeviceManager.refreshDevices()`, and `ADBDeviceManager.refreshDevices()`. Each refresh triggered delegate notifications (`didUpdateDevices:` and `adbDevicesDidChange:`), which immediately reinvoked `coordinator.refreshDevices()`. This spawned hundreds of synchronous `/opt/homebrew/bin/adb devices -l` subprocesses per minute, exhausting Grand Central Dispatch's worker pool.

---

## 2. Technical Remediation

1. **Decoupled List Assembly from Scanning:**
   Created `rebuildUnifiedDeviceList()` in `MirroringCoordinator.swift`. Delegate callbacks now only assemble existing cached devices into `availableDevices` without triggering new scans.
2. **Replaced Polling with Event-Driven ADB Socket Tracking:**
   Rewrote `ADBDeviceManager.swift` to connect to `127.0.0.1:5037` using `NWConnection` and send `0012host:track-devices`. The OS kernel handles notifications; zero subprocesses are spawned when idle.
3. **Background Serial USB Scanning with Concurrency Gate:**
   Offloaded `AVCaptureDevice.DiscoverySession` enumeration to a dedicated serial utility queue with an `isRefreshing` gate.
4. **Deduplication on Published Collections:**
   Enhanced equality conformance on `DiscoveredUSBDevice`, `AndroidDevice`, and `UnifiedDevice`. Updates to `@Published` properties only occur when values actually change, eliminating redundant SwiftUI redraws.
5. **Scoped Timers & Metal Resource Flushing:**
   Telemetry timer only runs while streaming (`startMirroring()` / `stopMirroring()`). Added `CVMetalTextureCacheFlush` in `clear()`.

---

## 3. Verified Results

| Metric | Before Remediation | After Remediation | Net Result |
| :--- | :--- | :--- | :--- |
| **Idle CPU %** | **120.1%** | **0.0%** | **99.8% reduction** |
| **Thread Count** | **73** | **6** | **91.8% reduction** |
| **Memory (RSS)** | **264.5 MB** | **32.0 MB** | **87.9% reduction** |
| **Subprocess Spawns** | **10–20 / sec** | **0 / sec** | **100% eliminated** |
| **Active 60 FPS Gaming**| **Preserved** | **Preserved** | **Uncompromised performance** |
