# CastSprint macOS — Idle CPU Profiling Report

## Methodology & Test Environment
- **Hardware:** Apple Silicon MacBook Air (M-Series, arm64)
- **OS:** macOS 14+ / Darwin 26.0
- **App Executable:** `/Applications/CastSprint.app/Contents/MacOS/CastSprintMac`
- **Build Mode:** Release (`swift build -c release`, ad-hoc signed, hardened runtime compatible)
- **Profiling Tools:**
  - `top -pid <PID> -l 10 -s 1 -stats pid,command,cpu,th,mem`
  - `/usr/bin/sample <PID> 5`
  - macOS Activity Monitor (Process Sampling & Inspection)
  - Diagnostic Probe (`CastSprintProbe`)

---

## 1. 60-Second Idle Profile: Baseline vs. Optimized

### Baseline (Prior to Fix — PID 92600 / 28324)
| Metric | Baseline (Idle) | Observation |
| :--- | :--- | :--- |
| **CPU Usage** | **120.1% – 121.7%** | Sustained pegged CPU across multiple cores |
| **Active Threads** | **73 threads** | Thread explosion, hitting GCD 64-worker soft limit |
| **Resident Memory (RSS)** | **264.5 MB** | High memory due to hundreds of queued dispatch blocks and pipe buffers |
| **Virtual Memory** | **466.50 GB** | Normal Mach virtual space allocation |
| **GPU Utilization** | **0.0%** | Metal view idle, no frame rendering |
| **Idle Wakeups** | **68 – 2,322 / sec** | Severe timer and dispatch queue churn |

### Optimized (After Fix — PID 50886)
| Metric | Optimized (Idle) | Improvement |
| :--- | :--- | :--- |
| **CPU Usage** | **0.0% – 0.2%** | **99.8% reduction** (well below 5% target) |
| **Active Threads** | **6 threads** | **91.8% reduction** (pure system baseline) |
| **Resident Memory (RSS)** | **29.0 MB** | **89.0% reduction** (lightweight native footprint) |
| **Virtual Memory** | **338 GB** | Clean native footprint |
| **GPU Utilization** | **0.0%** | `mtkView.isPaused = true`, zero idle GPU draws |
| **Idle Wakeups** | **0 – 1 / sec** | Completely quiescent event-driven wait |

---

## 2. Real Profiling Traces

### A. Pre-Fix Stack Sample (1,076 samples over 5 seconds)
```text
Dispatch Thread Soft Limit: 64 reached in 51 of 1076 samples -- too many dispatch threads blocked in synchronous operations

Call graph:
    1076 Thread_8842602   DispatchQueue_1: com.apple.main-thread  (serial)
    + 998 __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__  (in CoreFoundation) + 60
    +   998 _dispatch_main_queue_callback_4CF  (in libdispatch.dylib) + 944
    +     998 specialized closure #1 in USBDeviceManager.refreshDevices()  (in CastSprintMac) + 404
    64 Thread_8842710 ... Thread_8842774 (GCD Worker Threads)
    + 64 -[NSConcreteTask waitUntilExit]  (in Foundation) + 332
    +   64 _NSReadFromFileDescriptorWithProgress  (in Foundation) + 180
    +     64 read  (in libsystem_kernel.dylib) + 8
```

### B. Post-Fix Stack Sample (4,276 samples over 5 seconds)
```text
Call graph:
    4276 Thread_8877493   DispatchQueue_1: com.apple.main-thread  (serial)
    + 4276 mach_msg2_trap  (in libsystem_kernel.dylib) + 8  [0x19c968c20]
    4276 Thread_8877567: com.apple.NSEventThread
    + 4276 mach_msg2_trap  (in libsystem_kernel.dylib) + 8  [0x19c968c20]
    4276 Thread_8877627: com.apple.audio.toolbox.AUScheduledParameterRefresher
    + 4276 mach_msg2_trap  (in libsystem_kernel.dylib) + 8  [0x19c968c20]
    4276 Thread_8877635: com.apple.CFSocket.private
    + 4276 poll  (in libsystem_kernel.dylib) + 8
```

**Observation:** Every single thread is 100% blocked in kernel traps (`mach_msg2_trap` and `poll`) awaiting real hardware or OS events. No user-space loops, no spinning, no periodic polling, no dispatch queue congestion.

---

## 3. Real `top` Sampling Sequence (PID 50886)
Sampled over 10 consecutive seconds:
```text
PID    COMMAND       %CPU #TH MEM
50886  CastSprintMac 0.0  6   29M
50886  CastSprintMac 0.0  6   29M
50886  CastSprintMac 0.0  6   29M
50886  CastSprintMac 0.0  6   29M
50886  CastSprintMac 0.0  6   29M
50886  CastSprintMac 0.0  6   29M
50886  CastSprintMac 0.0  6   29M
50886  CastSprintMac 0.0  6   29M
50886  CastSprintMac 0.2  6   29M
50886  CastSprintMac 0.0  6   29M
```

## 4. Conclusion
The optimization delivers an **average idle CPU of 0.02%**, eliminating 100% of the CPU regression and ensuring that CastSprint behaves as a premier, whisper-quiet native macOS desktop application.

---

## 5. 2026-10-15 stability-pass verification

The installed 0.3.2 build was sampled again after the memory/GPU safety work:

- approximately 40 minutes idle before the second pass: 0.0% CPU, 72 MiB RSS;
- freshly reinstalled performance-pass binary: 0.0% CPU, 109 MiB RSS at 3 seconds;
- after 28 seconds: 0.0% CPU, 90 MiB RSS;
- three-second stack sample: 1,997 of 2,034 main-thread samples sleeping in `mach_msg2_trap`;
- no CastSprint error or fault entries during the short observation.

Additional fixes in this pass:

- Wireless ADB Pair/Connect commands run off the UI thread and time out after eight seconds.
- Android screenrecord restart uses exponential backoff capped at eight seconds.
- Android encoded-stream admission is capped at four pending chunks.
- Annex-B parsing compacts its buffer once per batch instead of once per NAL unit.

These results verify an idle, non-spinning application. Real iPhone/Android capture and OBS load remain **NOT_TESTED** on this exact binary and must not be inferred from idle measurements.
