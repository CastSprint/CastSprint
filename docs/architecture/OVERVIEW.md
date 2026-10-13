# Architecture Overview

CastSprint mirrors an Android 10+ screen to a Windows 10/11 PC over USB (via `adb reverse`) or LAN.
Everything runs locally: no accounts, no cloud, no telemetry, no watermarks.

## Components

| Layer | Android (sender) | Windows (receiver) | Shared |
|---|---|---|---|
| Capture | MediaProjection → VirtualDisplay | — | — |
| Encode | MediaCodec H.264 (Surface input) | — | — |
| Audio (Phase 4) | AudioPlaybackCapture + MediaCodec | WASAPI render | — |
| Transport | TCP client (Kotlin) | TCP server (Winsock) | Protocol v1 spec + `native/protocol` |
| Decode | — | Media Foundation H.264 MFT (DXVA, D3D11 surfaces) | — |
| Render | — | Direct3D 11 + DXGI flip-model swap chain | — |
| Record (Phase 5) | — | Media Foundation Sink Writer (remux, no re-encode) | — |
| UI | Framework Activity + Foreground Service | Win32 shell (WinUI 3 evaluated later) | — |

## Repository layout

```
apps/android     Gradle (Kotlin DSL) app, applicationId com.castsprint.android
apps/windows     C++20 Win32 receiver (CMake target castsprint_receiver)
native/protocol  Portable C++20 codec for Protocol v1 (no platform deps)
tests/protocol   Codec tests (CTest)
docs/            Architecture, development, testing docs
.github/         CI workflows and assistant instructions
```

`native/transport` and `native/common` will be added when real code exists for them (Phase 2);
empty modules are intentionally not created.

## Portability

- `native/protocol` is pure ISO C++20 — reusable by a future macOS receiver.
- Windows-specific code is confined to `apps/windows`. A macOS receiver would be `apps/macos`
  (VideoToolbox + Metal) sharing protocol/transport.
- An iOS sender would implement the same wire protocol (ReplayKit + VideoToolbox).

See [STREAMING_PIPELINE.md](STREAMING_PIPELINE.md), [PROTOCOL.md](PROTOCOL.md),
[THREADING.md](THREADING.md), [SECURITY.md](SECURITY.md).
