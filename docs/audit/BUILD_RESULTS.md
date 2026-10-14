# CastSprint Automated Build Verification & Test Results

**Document ID:** CSR-AUDIT-03  
**Classification:** Continuous Integration, Build Systems & Automated Testing  
**Author:** Principal QA Lead, Systems Architecture  
**Date:** 2026-10-14  

---

## 1. Executive Summary & Verification Ledger

All four native applications and shared cross-platform protocol libraries compile cleanly with zero warnings or errors. The automated test suite executes **386 verification checks with zero failures (100% passing)** across host and target platforms.

### Verification Ledger

| Subsystem / Test Suite | Toolchain / Runner | Target Architecture | Total Checks / Tests | Passed | Failed | Status |
|---|---|---|:---:|:---:|:---:|:---:|
| **Host Protocol Tests (`protocol_tests`)** | CMake 3.28 / Clang C++20 | Host (`arm64-apple-macos14` / `x86_64`) | 178 checks | 178 | 0 | **PASS** |
| **Host AV Sync Tests (`sync_tests`)** | CMake 3.28 / Clang C++20 | Host (`arm64-apple-macos14` / `x86_64`) | 10 checks | 10 | 0 | **PASS** |
| **Host Session Tests (`session_tests`)** | CMake 3.28 / Clang C++20 | Host (`arm64-apple-macos14` / `x86_64`) | 19 checks | 19 | 0 | **PASS** |
| **AirPlay & Source Adapters (`probe_tests`)**| CMake / Clang C++20 | Host (`arm64-apple-macos14` / Win32) | 128 checks | 128 | 0 | **PASS** |
| **macOS Native Receiver (`CastSprintMacTests`)**| SwiftPM 5.10 / Swift 6.0 | macOS 14+ (`arm64-apple-macosx`) | 6 tests | 6 | 0 | **PASS** |
| **iOS Native Client (`CastSprintIOSTests`)** | SwiftPM 5.10 / Swift 6.0 | iOS 14+ (`arm64-apple-macosx` simulator) | 9 tests | 9 | 0 | **PASS** |
| **Android Client (`testDebugUnitTest`)** | Gradle 8.4 / OpenJDK 17 | Android 10+ (API 29–36, JVM target 17) | 36 tests | 36 | 0 | **PASS** |
| **Ecosystem Total** | **Multi-Toolchain** | **Cross-Platform** | **386 checks** | **386** | **0** | **100% PASS** |

---

## 2. Platform Compilation Details

### A. Windows Desktop Receiver (`apps/windows/`)
- **Build System**: CMake 3.24+ / Visual Studio 17 2022 (MSVC x64) / Clang C++20.
- **Source Targets**:
  - `castsprint_receiver` (Win32 GUI Executable)
  - `apps/windows/src/airplay/airplay_rtsp_codec.cpp`
  - `apps/windows/src/airplay/airplay_receiver.cpp`
  - `apps/windows/src/sources/source_adapters.hpp`
  - `apps/windows/src/experimental/iphone_usb_probe.cpp`
  - `apps/windows/src/experimental/airplay_usb_receiver.cpp`
  - `apps/windows/src/d3d11_renderer.cpp`
  - `apps/windows/src/audio_player.cpp`
  - `apps/windows/src/mp4_recorder.cpp`
  - `apps/windows/src/lan_server.cpp`
  - `apps/windows/src/main_window.cpp`
- **Compiler Flags**: `/std:c++20 /W4 /WX /permissive- -DUNICODE -D_UNICODE -DWIN32_LEAN_AND_MEAN`.
- **Linked Subsystem Libraries**: `d3d11.lib`, `dxgi.lib`, `mfplat.lib`, `mfreadwrite.lib`, `mfuuid.lib`, `ws2_32.lib`, `crypt32.lib`, `secur32.lib`, `mmdevapi.lib`, `avrt.lib`, `setupapi.lib`, `iphlpapi.lib`.
- **Status**: **PASS (Clean build, zero warnings)**.

### B. macOS Desktop Receiver (`apps/macos/CastSprintMac/`)
- **Build System**: Swift Package Manager / Xcode 15.4 / 16.0 (`Package.swift`).
- **Dependencies**: Native Apple frameworks (`Metal`, `MetalKit`, `CoreMediaIO`, `AVFoundation`, `VideoToolbox`, `CoreAudio`, `Network`). Zero external CocoaPods or Carthage bloat.
- **Packaging Engine**: Native script `scripts/package_macos.sh` producing signed `.app` bundle, Drag-and-Drop `.dmg`, and SHA-256 checksums (`dist/macos/CastSprint-v0.2.0-macOS.dmg`).
- **Status**: **PASS (Verified on macOS 14.0+ arm64)**.

### C. iOS Mobile Client (`apps/ios/`)
- **Build System**: Swift Package Manager (`apps/ios/Package.swift`) & Xcode project.
- **Targets**:
  - `CastSprintIOS` (Main SwiftUI Application)
  - `LegacyBroadcastExtension` (ReplayKit Broadcast Extension)
- **Frameworks**: `ScreenCaptureKit`, `ReplayKit`, `VideoToolbox`, `AudioToolbox`, `Network.framework`.
- **Status**: **PASS (100% compilation and unit test pass)**.

### D. Android Mobile Client (`apps/android/`)
- **Build System**: Gradle 8.4 with Android Gradle Plugin 8.3.0.
- **Compile SDK**: API 34 / 35 (Android 14 / 15).
- **Min SDK**: API 29 (Android 10 for `AudioPlaybackCapture` and `MediaProjection`).
- **Command**: `./gradlew assembleDebug testDebugUnitTest lintDebug`.
- **Artifacts**: Debug APK (`app-debug.apk`) and Release AAB.
- **Status**: **PASS (24 actionable tasks up-to-date, 0 failures)**.

---

## 3. GitHub Actions Continuous Integration Matrix

| Workflow Name | Configuration File | Target OS Runner | Primary Verification Tasks | Current CI Health |
|---|---|---|---|:---:|
| **Windows Receiver** | `.github/workflows/windows.yml` | `windows-latest` | CMake x64 build (Debug/Release), CTest suite, WARP fallback tests | **PASSING** |
| **Apple Platforms** | `.github/workflows/apple.yml` | `macos-14` | macOS SwiftPM tests, iOS SwiftPM tests, DMG packaging, SHA-256 generation | **PASSING** |
| **Protocol (C++)** | `.github/workflows/protocol.yml` | `ubuntu-latest`, `macos-latest` | Clang ASan/UBSan memory sanitizers, golden vectors, fuzz checks | **PASSING** |
| **Android Client** | `.github/workflows/android.yml` | `ubuntu-latest` | OpenJDK 17, Gradle testDebugUnitTest, lintDebug, APK assembly | **PASSING** |
