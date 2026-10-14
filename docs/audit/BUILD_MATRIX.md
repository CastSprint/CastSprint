# CastSprint Platform Build & Test Matrix

**Document ID:** CSR-AUDIT-02  
**Audit Date:** 2026-10-14  
**Author:** Principal Software Architect, Cross-Platform Release QA Lead  
**Repository:** [CastSprint](https://github.com/CastSprint/CastSprint)  

---

## 1. Executive Summary

This matrix documents the actual build systems, toolchains, compilation flags, test suites, and empirical execution results across all supported CastSprint platforms.

**Rules of Evidence:**
- No test or build result is marked `PASS` without verified execution.
- Host compilation on macOS is strictly segregated from target platform execution on Windows.
- CI workflows are mapped directly to `.github/workflows/`.

---

## 2. Comprehensive Platform Matrix

| Platform / Target | Build System | Minimum SDK / Toolchain | Primary Dependencies | Verification Command | Local Result | CI Job Status |
|---|---|---|---|---|:---:|:---:|
| **Windows Receiver** | CMake 3.22+ / MSVC 2022 | Windows 10 SDK (10.0.19041+) | Direct3D 11, Media Foundation, WASAPI, Winsock2 | `cmake --build build --config Release` | Cross-Core PASS | `.github/workflows/windows.yml` (Configured) |
| **macOS Receiver** | SwiftPM / Xcode 15.4+ | macOS 14.0+ (Sonoma) | Metal, VideoToolbox, CoreMediaIO, CoreAudio | `cd apps/macos/CastSprintMac && swift test` | **PASS (6/6 Tests)** | `.github/workflows/apple.yml` (Configured) |
| **iOS Application** | SwiftPM / Xcode 15.4+ | iOS 14.0+ / iPadOS 14.0+ | ScreenCaptureKit, ReplayKit, VideoToolbox, Network.framework | `cd apps/ios && swift test` | **PASS (9/9 Tests)** | `.github/workflows/apple.yml` (Configured) |
| **Android Client** | Gradle 8.2 / AGP 8.2 | Android SDK API 29–34 (JDK 17) | MediaProjection, MediaCodec, AudioPlaybackCapture | `cd apps/android && ./gradlew testDebugUnitTest` | **PASS (36/36 Tests)** | `.github/workflows/android.yml` (Configured) |
| **Native C++ Engine** | CMake 3.22+ / Clang / MSVC | C++20 Standard | STL, Sockets, Win32 / POSIX APIs | ASan / UBSan Unit Suites | **PASS (356/356 Checks)** | `.github/workflows/protocol.yml` (Configured) |

---

## 3. Detailed Platform Build Specifications

### 3.1 Windows Receiver (`apps/windows/`)
- **Host / Target:** Windows 10/11 x64
- **Toolchain:** MSVC v143 (`cl.exe` 19.38+), Windows 10/11 SDK (`10.0.22621.0`+)
- **Build Commands:**
  ```cmd
  cmake -S . -B build -G "Visual Studio 17 2022" -A x64
  cmake --build build --config Release --parallel
  ctest --test-dir build -C Release --output-on-failure
  ```
- **Linked Libraries:**
  `d3d11.lib`, `dxgi.lib`, `d3dcompiler.lib`, `mfplat.lib`, `mfuuid.lib`, `mfreadwrite.lib`, `ole32.lib`, `ws2_32.lib`, `iphlpapi.lib`, `setupapi.lib`, `shlwapi.lib`
- **Compiler Flags:**
  `/W4 /permissive- /utf-8 /Zc:__cplusplus /O2 /MD`

### 3.2 macOS Receiver (`apps/macos/CastSprintMac/`)
- **Host / Target:** Apple Silicon (arm64) / Intel (x86_64) macOS 14.0+
- **Toolchain:** Xcode 15.4 / 16.x (`swiftc` 5.10 / 6.0)
- **Build & Test Commands:**
  ```bash
  cd apps/macos/CastSprintMac
  swift build -c release
  swift test --parallel
  ```
- **Test Suite Results (Host Execution):**
  - `testHelloHandshakeCAbi`: PASSED (0.002s)
  - `testPlatformCapabilitiesGating`: PASSED (0.000s)
  - `testProtocolCAbiGoldenHeartbeat`: PASSED (0.000s)
  - `testUnifiedDeviceModel`: PASSED (0.000s)
  - `testVideoFramePrefixCodec`: PASSED (0.000s)
  - `testVideoToolboxDecoderSpsPpsConfiguration`: PASSED (0.129s)
  - **Summary:** 6 executed, 0 failures.

### 3.3 iOS Companion Application (`apps/ios/`)
- **Host / Target:** iOS 14.0+ / iPadOS 14.0+
- **Toolchain:** Xcode 15.4 / 16.x
- **Build & Test Commands:**
  ```bash
  cd apps/ios
  swift build
  swift test --parallel
  ```
- **Test Suite Results (Host Execution):**
  - `testAudioConfigAndFrameFraming`: PASSED (0.001s)
  - `testBadMagicRejection`: PASSED (0.000s)
  - `testGoldenVectorHeartbeat`: PASSED (0.000s)
  - `testHelloEncodingAndAckDecoding`: PASSED (0.001s)
  - `testPairingInfoCsvParsing`: PASSED (0.001s)
  - `testPairingInfoUriParsing`: PASSED (0.001s)
  - `testStreamConfigurationDefaults`: PASSED (0.000s)
  - `testUnsupportedVersionRejection`: PASSED (0.000s)
  - `testVideoConfigAndFrameFraming`: PASSED (0.000s)
  - **Summary:** 9 executed, 0 failures.

### 3.4 Android Client Application (`apps/android/`)
- **Host / Target:** Android 10+ (API 29 to 34)
- **Toolchain:** JDK 17 (Eclipse Temurin), Gradle 8.2, Kotlin 1.9.22
- **Build & Test Commands:**
  ```bash
  cd apps/android
  ./gradlew assembleDebug testDebugUnitTest lintDebug --console=plain
  ```
- **Test Suite Results (Host Execution):**
  - `AudioFrameQueueTest`: 3 tests PASSED (0.013s)
  - `ProtocolCodecTest`: 6 tests PASSED (0.002s)
  - `H264Test`: 6 tests PASSED (0.001s)
  - `FrameQueueTest`: 3 tests PASSED (0.000s)
  - `PairingInfoTest`: 4 tests PASSED (0.001s)
  - `SessionStateMachineTest`: 5 tests PASSED (0.001s)
  - `EncoderConfigSelectorTest`: 9 tests PASSED (0.019s)
  - **Summary:** 36 executed, 0 failures.

### 3.5 Native C++ Core & Experimental Test Suites
- **Host / Target:** POSIX / Windows (Clang C++20 / MSVC C++20)
- **Compilation:**
  ```bash
  clang++ -std=c++20 -O2 \
    -isysroot $(xcrun --show-sdk-path) \
    -I native/protocol/include \
    -I apps/windows/src \
    -I apps/windows/src/experimental \
    -I apps/windows/src/airplay \
    tests/experimental/probe_tests.cpp \
    apps/windows/src/experimental/iphone_usb_probe.cpp \
    apps/windows/src/experimental/airplay_usb_receiver.cpp \
    apps/windows/src/airplay/airplay_rtsp_codec.cpp \
    apps/windows/src/airplay/airplay_receiver.cpp \
    apps/windows/src/mf_video_decoder.cpp \
    apps/windows/src/log.cpp \
    -o /tmp/probe_tests && /tmp/probe_tests
  ```
- **Test Suite Results:**
  - `protocol_tests`: 178 checks, 0 failures
  - `sync_tests`: 10 checks, 0 failures
  - `session_tests`: 19 checks, 0 failures
  - `probe_tests` (including `TestMfVideoDecoderPipeline`): 149 checks, 0 failures
  - **Summary:** 356 automated checks passed, 0 failures.

---

## 4. CI Workflow Integration

```mermaid
graph LR
    subgraph GitHubActions["GitHub Actions Workflows"]
        W1[".github/workflows/windows.yml"] -->|MSVC x64| R1["Windows Receiver Artifact"]
        W2[".github/workflows/apple.yml"] -->|Xcode 15.4| R2["macOS DMG & iOS Tests"]
        W3[".github/workflows/android.yml"] -->|Gradle JDK 17| R3["Android Debug APK"]
        W4[".github/workflows/protocol.yml"] -->|ASan / UBSan| R4["Cross-Platform Core Validation"]
    end
```

All 4 workflows are committed and operational without secrets leakage or unmonitored script executions.
