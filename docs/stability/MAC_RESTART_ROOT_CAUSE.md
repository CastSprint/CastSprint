# Mac restart root-cause report

## Verdict

**VERIFIED:** macOS restarted because of a kernel watchdog panic while virtual-memory compression and swap were exhausted.

**LIKELY MATERIAL CONTRIBUTOR:** CastSprintMac retained about 20.13 GB after about 372 seconds on a 16 GiB Mac. It was overwhelmingly the largest resident process in the panic snapshot.

**UNCONFIRMED:** the exact allocation type responsible. Instruments Allocations/VM Tracker is required to distinguish IOSurface, command-buffer, pixel-buffer, or other retained allocations.

## Evidence

- Panic: `/Library/Logs/DiagnosticReports/panic-full-2026-10-15-214909.0002.panic`
- Time: 2026-10-15 21:49:09 +0600
- macOS: 27.0 (26A428), Mac16,12, 16 GiB RAM
- Panic string: `watchdog timeout: no checkins from watchdogd in 94 seconds`
- VM state: 20% compressed-pages limit (OK), **100% segment limit (BAD)**, 23 swapfiles, LOW swap space
- CastSprintMac: 20,131,415,144 resident bytes; 371.99 s uptime
- OBS: 251,463,312 resident bytes
- WindowServer: about 1.02 GB resident

The panicked task was `chronod`, but the backtrace contains Apple watchdog/interrupt code and does not prove that `chronod` caused the memory pressure. No AGX/GPU panic signature was present.

## Remediation

- Capture discards late frames.
- Metal work is capped at three in-flight command buffers.
- CAMetalLayer drawables are capped at two and use drawable timeout.
- Hidden OBS output detaches from the renderer.
- Audio scheduling and recording sample queues are bounded.
- Stale work is dropped under backpressure.

## Validation status

- **VERIFIED:** source builds in release mode.
- **NOT_TESTED:** sustained real-device capture after the fix. Run only the staged procedure in `docs/testing/SAFE_HARDWARE_VALIDATION.md`.

