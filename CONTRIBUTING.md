# Contributing to CastSprint

Thank you for your interest in contributing to **CastSprint**! CastSprint is an open-source, high-performance native gaming screen and audio mirroring tool. We welcome contributions from developers, testers, and documentation writers.

---

## Core Principles

1. **Keep Layers Decoupled**:
   - `capture`: Native Android `MediaProjection` and `AudioPlaybackCapture`.
   - `encode`: Android hardware `MediaCodec` (H.264 video, AAC-LC audio).
   - `transport`: Bounded SPSC queues, TCP socket sinks, and TLS SChannel listener.
   - `decode`: Windows Media Foundation AAC MFT and Direct3D 11 video decoder.
   - `render`: Windows Direct3D 11 flip-model swapchain (`DXGI_SWAP_EFFECT_FLIP_DISCARD`).
   - `sync`: Monotonic clock linear regression (`AvSynchronizer`).
   - `record`: Native Media Foundation Sink Writer MP4 muxer (`Mp4Recorder`).
   - `UI`: Native Win32 GDI dashboard and Android Jetpack UI.

2. **Performance First**:
   - Zero unnecessary heap allocations in the real-time hot path.
   - Bounded queues only. Never buffer unbounded video or audio frames.
   - Never fake measurements. Performance claims must include reproducible benchmarks, test methodology, and hardware specifications.

3. **Privacy & Freedom First**:
   - No telemetry, analytics trackers, advertising SDKs, or cloud dependencies will ever be accepted into the codebase.
   - No microphone eavesdropping; audio capture must remain strictly playback loopback (`AudioPlaybackCapture`).

---

## Coding Standards

### C++ (Native Engines & Windows Client)
- **Standard**: Modern C++20 (`std::span`, `std::chrono`, `std::unique_ptr`).
- **Safety**: RAII for every native operating system handle (`ComPtr<T>`, `wil::unique_handle`, custom socket wrappers). Zero raw `new` / `delete`.
- **Compiler Warnings**: Must build warning-free:
  - MSVC: `/W4 /WX`
  - Clang / GCC: `-Wall -Wextra -Wconversion -Werror`
- **Formatting**: Clang-format adhering to the repository `.clang-format` configuration.

### Kotlin (Android Client)
- **Style**: Follow standard [Kotlin Style Guide](https://developer.android.com/kotlin/style-guide).
- **Architecture**: Clean MVVM / Service separation. The background `ScreenCaptureService` must remain fully responsive and respect foreground service lifecycle mandates on Android 10 through Android 15.
- **Dependencies**: Keep minimal. Avoid pulling in heavyweight third-party dependencies when native Android APIs suffice.

### Swift (macOS & iOS Clients)
- **Standard**: Swift 6 strict concurrency compliance (`@MainActor`, `Sendable` types).
- **Public APIs Only**: Use exclusively documented Apple public frameworks (AVFoundation, CoreMediaIO, VideoToolbox, AudioToolbox, Network.framework, Metal). Zero private Apple headers or reverse-engineered kernel drivers.
- **Memory Ceiling**: iOS ReplayKit Broadcast Extensions (`apps/ios/LegacyBroadcastExtension`) must strictly operate under Apple's 50 MB resident memory ceiling. Avoid heap allocations or buffer accumulation in `processSampleBuffer`.
- **Formatting**: Adhere to official Apple Swift API Design Guidelines.
- **Security**: Never embed signing certificates, provisioning profiles, or developer credentials in Git.

### CastSprint Protocol (`CSP1`) Changes
- The binary wire protocol is defined in [`docs/architecture/PROTOCOL.md`](docs/architecture/PROTOCOL.md).
- Any modifications to packet structure, headers, or opcodes must update:
  1. `docs/architecture/PROTOCOL.md` specification.
  2. C++ protocol codec in `native/protocol/`.
  3. Kotlin protocol codec in `apps/android/app/src/main/java/com/castsprint/android/protocol/`.
  4. Swift protocol implementation in `apps/macos/CastSprintMac/Sources/CastSprintMac/Protocol/` and `apps/ios/CastSprintIOS/Sources/CastSprintIOS/Protocol/`.
  5. Cross-language golden vector test suites across all native, Android, and Apple test suites.
- Breaking changes require bumping the protocol version identifier.

---

## Development & Testing Workflow

Before opening a pull request, verify all automated test suites pass locally without errors or warnings:

### 1. Host Native Protocol & Engine Tests
```bash
cmake -S . -B build/host
cmake --build build/host
ctest --test-dir build/host --output-on-failure
```
Ensure all protocol, AV synchronization, and session management tests pass.

### 2. Android Unit Tests & Lint
```bash
cd apps/android
./gradlew testDebugUnitTest lintDebug
```
Ensure 100% test pass rate and zero lint errors.

### 3. macOS Receiver Build & Tests
```bash
swift test --package-path apps/macos/CastSprintMac
./scripts/package_macos.sh
```
Ensure all macOS unit tests pass and the release `.dmg` builds cleanly.

### 4. iOS Client Build & Tests
```bash
swift test --package-path apps/ios/CastSprintIOS
```
Ensure all iOS unit tests and golden vector tests pass.

### 5. Windows Native Build (Windows Machine)
```bash
cmake -S . -B build/win -G "Visual Studio 17 2022" -A x64
cmake --build build/win --config Release
```

---

## Submitting Pull Requests

1. **Fork and branch**: Create a descriptive feature branch from `main` (e.g., `feature/av1-encoding` or `fix/wasapi-sample-rate`).
2. **Commit messages**: Use conventional commit formatting (e.g., `feat(audio): add support for 44.1kHz sample rate fallback`).
3. **Documentation**: Update relevant architecture docs, troubleshooting guides, and `CHANGELOG.md` when adding or modifying user-facing features.
4. **No Git push without approval**: When using autonomous AI coding tools, ensure human verification before pushing tags or committing to remote branches.
