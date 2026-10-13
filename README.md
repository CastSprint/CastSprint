# CastSprint

Free, private, low-latency Android → Windows screen mirroring, built natively for mobile gaming
and OBS streaming.

- Free forever — no premium tier, accounts, ads, or watermarks
- Local only — USB (`adb reverse`) or LAN; works offline; no cloud
- Native — Kotlin/MediaCodec on Android, C++20/Direct3D 11/Media Foundation on Windows

> **Status:** Phase 1 (foundation). Mirroring is not functional yet — see
> [docs/PROGRESS.md](docs/PROGRESS.md) and [docs/ROADMAP.md](docs/ROADMAP.md).

## Requirements
Android 10+ phone · Windows 10/11 x64 PC.

## Build
See [docs/development/SETUP.md](docs/development/SETUP.md).

```bash
# Protocol library + tests (any OS)
cmake -S . -B build/host && cmake --build build/host && ctest --test-dir build/host
# Android
cd apps/android && ./gradlew assembleDebug testDebugUnitTest
```
Windows: `cmake -S . -B build/win -G "Visual Studio 17 2022" -A x64 && cmake --build build/win`.

## Documentation
- [Architecture overview](docs/architecture/OVERVIEW.md)
- [Streaming pipeline](docs/architecture/STREAMING_PIPELINE.md)
- [Protocol v1](docs/architecture/PROTOCOL.md)
- [Threading](docs/architecture/THREADING.md) · [Security](docs/architecture/SECURITY.md)

## License
Not yet chosen — see [docs/development/LICENSING.md](docs/development/LICENSING.md).
