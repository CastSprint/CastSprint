# Progress

## Phase 1 — Foundation (2026-10-13)

| Item | Status | Verified on |
|---|---|---|
| Protocol v1 spec (`docs/architecture/PROTOCOL.md`) | Done | — |
| C++20 protocol codec (`native/protocol`) | Done | macOS arm64, AppleClang 21, `-Wall -Wextra -Wconversion -Werror` |
| Protocol tests (round-trip, invalid packets, versions, golden vector) | Pass | macOS (CTest); also run under ASan/UBSan |
| Kotlin protocol subset + JVM tests (shared golden vector) | Pass | `./gradlew testDebugUnitTest` |
| Android app (`com.castsprint.android`) assemble + lint | Pass | AGP 8.13.2, Gradle 8.13, JDK 17 |
| Windows Win32 + D3D11 receiver shell | Written, **not compiled locally** | Pending: Windows/MSVC (CI `windows.yml`) |
| Windows `--smoke-test` startup test | Written, **not run locally** | Pending: Windows |
| GitHub Actions workflows | Written, not yet run | Needs push |
| License | **Decision pending** | see `docs/development/LICENSING.md` |

## Phase 2 — Android Capture & Hardware Encoding (2026-10-14)

| Item | Status | Verified on |
|---|---|---|
| MediaProjection + FGS lifecycle (`ScreenCaptureService`) | Done | Android 10+ / Android 14+ FGS compliance, tested on API 36.1 |
| Zero-copy VirtualDisplay -> Surface -> MediaCodec pipeline | Done | Hardware/software AVC encoder, surface input |
| Dynamic capability query & fallback (`EncoderConfigSelector`) | Done | 6 unit tests; verified on emulator (`c2.android.avc.encoder`) |
| Bitstream normalization & Annex-B framing (`H264.kt`) | Done | 6 unit tests; SPS/PPS extraction, IDR detection |
| SPSC bounded buffer queue & backpressure (`FrameQueue`) | Done | 3 unit tests; frame dropping under load, IDR preservation |
| Protocol v1 transport sink (`TcpTransportSink`) | Done | Handshake, config, frame packets, heartbeat |
| Standalone H.264 file sink (`FileTransportSink`) | Done | Zero PC dependency test mode; valid Annex-B bitstream output |
| Native UI with branding, controls, and live stats | Done | Dark theme, resolution/FPS/bitrate/mode selectors, live stats |
| End-to-end device capture verification | Pass | Verified with `ffprobe` (864x1920, Constrained Baseline, valid NALs) |
| Unit test suite (24 tests) & Android lint | Pass | `./gradlew testDebugUnitTest lintDebug` (0 warnings/errors) |

## Next (Phase 3)
See [ROADMAP.md](ROADMAP.md) — Windows DXVA2/D3D11 Video Decoder & Desktop Renderer.

