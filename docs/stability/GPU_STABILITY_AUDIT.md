# GPU stability audit

## Findings

- **VERIFIED:** the panic is not an AGX/GPU panic; it is a watchdog panic under severe VM/swap pressure.
- **VERIFIED:** the former renderer could enqueue one Core Image/Metal command buffer for every frame and every output without an in-flight bound.
- **VERIFIED:** the clean OBS renderer stayed attached while hidden.
- **LIKELY:** retained drawables, textures, pixel buffers, and command-buffer closures amplified memory pressure when the GPU fell behind.

## Controls now implemented

- Three shared in-flight command-buffer permits per renderer.
- Nonblocking admission: late render work is dropped rather than queued.
- Completion handlers release permits for all successful submissions.
- `maximumDrawableCount = 2` and `allowsNextDrawableTimeout = true`.
- Hidden/closed OBS output is detached and reattached on demand.
- Telemetry counts render-backpressure drops.

## Remaining proof

**NOT_TESTED:** GPU Frame Capture, Metal System Trace, and a staged iPhone/OBS run on the repaired build. These are required before calling the issue fully closed.

