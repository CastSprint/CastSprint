# CastSprint Build & Automated Verification Guide

**Document ID:** CSR-BUILD-VERIFY-01  
**Classification:** Build Systems Engineering & Compilation Reference  
**Author:** Principal QA Lead, Systems Architecture  
**Date:** 2026-10-14  

---

## 1. Quick Verification Commands

From the root of the repository on a developer host:

```bash
# 1. Execute Host C++ Protocol, AV Sync, and Session Tests
./build/host/tests/protocol/protocol_tests
./build/host/tests/sync/sync_tests
./build/host/tests/session/session_tests

# 2. Execute Windows Experimental USB Probe & AirPlay Receiver Suite (128 checks)
xcrun -sdk macosx clang++ -std=c++20 -target arm64-apple-macos14.0 -I. -Inative/protocol/include \
  tests/experimental/probe_tests.cpp \
  apps/windows/src/experimental/iphone_usb_probe.cpp \
  apps/windows/src/experimental/airplay_usb_receiver.cpp \
  apps/windows/src/airplay/airplay_rtsp_codec.cpp \
  apps/windows/src/airplay/airplay_receiver.cpp \
  -o /tmp/probe_tests && /tmp/probe_tests

# 3. Execute macOS Native Receiver Tests
swift test --package-path apps/macos/CastSprintMac

# 4. Execute iOS Mobile Core Tests
swift test --package-path apps/ios

# 5. Execute Android Mobile Unit Tests
cd apps/android && ./gradlew testDebugUnitTest
```

---

## 2. Platform Compilation Specifications

### A. Windows 10/11 Desktop Receiver
- **Target OS**: Windows 10 (1903+) or Windows 11 x64.
- **Generator**: CMake 3.24+ with Visual Studio 2022 (MSVC).
- **Configure Command**:
  ```cmd
  cmake -S . -B build -G "Visual Studio 17 2022" -A x64
  ```
- **Build Command**:
  ```cmd
  cmake --build build --config Release --parallel
  ```
- **Target Output**: `build/apps/windows/Release/castsprint_receiver.exe`.

### B. macOS 14+ Desktop Receiver
- **Target OS**: macOS 14.0+ (Sonoma) or macOS 15.0+ (Sequoia) on Apple Silicon or Intel x86_64.
- **Toolchain**: Xcode 15.4+ / SwiftPM 5.10+.
- **Packaging Command**:
  ```bash
  bash scripts/package_macos.sh
  ```
- **Target Output**: `dist/macos/CastSprint-v0.2.0-macOS.dmg` (with verified SHA-256 checksum).

### C. iOS Mobile Streaming Client
- **Target OS**: iOS 14.0+ / iPadOS 14.0+ through iOS 18+.
- **Toolchain**: Xcode 15.4+ / Swift 5.10+.
- **Build & Test**:
  ```bash
  swift test --package-path apps/ios
  ```

### D. Android Mobile Streaming Client
- **Target OS**: Android 10+ (API 29+) through Android 15/16 (API 36).
- **Toolchain**: Android Studio Iguana+ / Gradle 8.4 / OpenJDK 17.
- **Build Command**:
  ```bash
  cd apps/android && ./gradlew assembleDebug testDebugUnitTest
  ```
- **Target Output**: `apps/android/app/build/outputs/apk/debug/app-debug.apk`.
