# Threading Model

Rules: no busy-waiting, bounded queues everywhere, every thread has an owner that joins it.

## Android sender

| Thread | Work | Hand-off |
|---|---|---|
| Main | UI, MediaProjection consent, service start/stop | — |
| Encoder callback (`HandlerThread`) | `MediaCodec.Callback.onOutputBufferAvailable` → copy AU into pooled buffer | Bounded queue (cap ~8 frames) |
| Network writer | Blocking socket writes, heartbeats | — |
| Network reader | Reads control messages (keyframe requests, DISCONNECT) | Posts to encoder handler |

Overflow policy: drop oldest non-key frames, set `DISCONTINUITY` flag on next frame, request sync frame.

## Windows receiver

| Thread | Work | Hand-off |
|---|---|---|
| UI (Win32 message loop) | Window, input, `GetMessage` (blocking) | — |
| Network reader | `recv` → header validation → payload | Bounded SPSC queue (cap 4–8) |
| Decoder | MF decoder `ProcessInput/ProcessOutput` | Latest-frame slot (mailbox, size 1) |
| Render | Waits on frame-latency waitable object, presents newest texture | — |

- Waiting uses `WaitForMultipleObjects`, condition variables, or the DXGI frame-latency waitable;
  never sleep-polling.
- Shutdown: set stop event → close socket (unblocks `recv`) → join reader → drain/flush decoder →
  join render → release D3D. RAII owners (`ComPtr`, `std::jthread`, unique handles).
- The D3D11 immediate context is used only by the render thread; the decoder shares the device
  through `IMFDXGIDeviceManager` with multithread protection enabled.

Phase 1 is single-threaded (UI thread renders on `WM_PAINT`).
