# CastSprint Project Technical Baseline

**Baseline Date:** 2026-10-14  
**Git Branch:** `audit/full-product-completion`  
**Base Commit Hash:** `355e9cb6f41076dc7e4c684663c3692425d2c5a0`  
**Host Environment:** Apple Silicon macOS (Darwin 27.0.0 arm64)  
**Standard:** Autonomous Zero-Optimism Technical Audit & Implementation  

---

## 1. Environment & Available Toolchains

- **Operating System:** macOS 14/15 / Darwin Kernel Version 27.0.0 (Apple Silicon arm64)
- **Xcode / Swift Toolchain:** Apple Swift version 6.3.2 (`swiftlang-6.3.2.1.108 clang-2100.1.1.101`), Xcode 15.4 / 16.x targeting `arm64-apple-macosx`
- **Java / Android Toolchain:** OpenJDK 17 (`javac 17.0.20.1`), Gradle 8.2 wrapper in `apps/android/gradlew`
- **Android Debug Bridge:** ADB version 1.0.41 (`37.0.1-15733141`) at `/opt/homebrew/bin/adb`
- **C++ Compiler:** Apple Clang (C++20 compliant) on host; MSVC v143 (Visual Studio 2022) in Windows CI (`windows-latest`)
- **License:** Apache License, Version 2.0 (`LICENSE` present in root)

---

## 2. Project Modules & Directory Layout

| Module Directory | Target Platform | Primary Technology | Description |
|---|---|---|---|
| `apps/android/` | Android 10+ (API 29–34) | Kotlin, Android SDK, MediaProjection, MediaCodec | Native Android capture and streaming client |
| `apps/ios/` | iOS 14.0+ / iPadOS | Swift, SwiftUI, ScreenCaptureKit, ReplayKit, VideoToolbox | Native iOS screen capture companion application |
| `apps/windows/` | Windows 10/11 x64 | C++20, Win32, Direct3D 11, Media Foundation, WASAPI | Native Windows receiver and streaming dashboard |
| `apps/macos/` | macOS 14.0+ (Sonoma) | Swift, AppKit, Metal, CoreMediaIO, VideoToolbox | Native macOS receiver and streaming dashboard |
| `native/` | Cross-Platform | C++20 (`protocol`, `sync`, `session`) | Core binary packet framing, AV sync, and session state machine |
| `tests/` | Cross-Platform | C++20, Swift, JUnit/Kotlin | Automated test suites for protocols, sync, and platform probes |
| `scripts/` | Cross-Platform | Shell / Python | Build and packaging automation scripts |
| `.github/workflows/` | CI Matrix | GitHub Actions | Workflows for Windows, Apple (macOS/iOS), Android, and Protocol |

---

## 3. Available Build Targets & Verification Methods

1. **Native C++ Protocol & Core Engines**:
   - `protocol_tests` (178 check assertions)
   - `sync_tests` (10 check assertions)
   - `session_tests` (19 check assertions)
   - `probe_tests` (149 check assertions)
   - Total: 356 automated assertions passing with 0 failures on host.
2. **macOS Application (`apps/macos/CastSprintMac`)**:
   - `swift test`: 6 test cases executed, 0 failures.
   - `swift build`: Compiles native release binaries.
   - `scripts/package_macos.sh`: Packages native `.app` and DMG distribution bundle.
3. **iOS Core Modules (`apps/ios`)**:
   - `swift test`: 9 test cases executed, 0 failures.
4. **Android Client (`apps/android`)**:
   - `./gradlew testDebugUnitTest`: 36 unit tests executed, 0 failures.
   - `./gradlew assembleDebug`: Compiles debug APK.
5. **Windows Receiver (`apps/windows`)**:
   - MSVC C++20 + CMake build in `.github/workflows/windows.yml`.
   - Core cross-platform logic and mock decoder pipeline validated on host via Clang C++20.

---

## 4. Known Platform Limitations & Physical Boundaries

1. **Windows Physical Testing**:
   - The developer environment is a macOS host. No physical Windows PC is locally attached.
   - Windows Direct3D 11 hardware presentation, WASAPI device enumeration, and OBS Game Capture hook execution must be validated via GitHub Actions CI and marked `NOT_TESTED (Physical Lab)` until verified on physical Windows hardware.
2. **Physical Device Attachment**:
   - At the time of baseline generation, no physical iPhone or Android device is attached via USB to the host machine. Device routes requiring physical tethering are labeled `NOT_TESTED (Physical Lab)` in accordance with zero-optimism guidelines.
3. **App-less AirPlay Protocol Cryptography**:
   - Production un-jailbroken iOS devices mandate SRP-6a / Ed25519 pairing handshakes and ChaCha20-Poly1305 stream decryption.
   - The native AirPlay receiver on Windows is kept strictly on an `EXPERIMENTAL` research track; the CastSprint iOS companion app over Wi-Fi is the designated production route for iPhone screen mirroring.
4. **Direct USB iPhone Mirroring on Windows**:
   - Structurally blocked on Windows due to Apple driver architecture (`usbaapl64.sys`) without replacing kernel drivers with WinUSB. This route remains designated as `BLOCKED / RESEARCH ONLY`.
