# CastSprint Cross-Platform Release Readiness & Packaging Specification

**Document ID:** CSR-REL-READINESS-01  
**Classification:** Release Engineering, Code Signing & Distribution Compliance  
**Author:** Principal Release Engineer, Systems Architect  
**Date:** 2026-10-14  

---

## 1. Executive Release Overview

CastSprint is prepared for public beta release across all four native applications under the **Apache License, Version 2.0**:
- **Release Version**: `v0.2.0-beta`
- **Guaranteed Product Policy**: Completely free forever, zero watermarks, zero subscription paywalls, zero accounts, zero cloud servers, zero mandatory advertisements.

---

## 2. Platform Release Packaging Checklists

### A. Windows Desktop Receiver (`apps/windows/`)
- [x] **x64 Release Compilation**: Compiles via MSVC with `/O2 /Oi /Gy` and link-time code generation (`/LTCG`).
- [x] **Direct3D 11 & Media Foundation Integration**: Fully native Win32 binary with hardware NV12 decoding and flip-model swapchain presentation.
- [x] **Application Resource & High-Res Icon**: Embedded Win32 icon resource (`resources/version.rc`, ID 101) with clean application branding.
- [x] **Zero Third-Party Kernel Drivers**: Uses WHQL-signed Microsoft and Apple drivers.
- [x] **Packaging Configurations**:
  - Standalone portable ZIP package (`CastSprint-v0.2.0-Windows-x64.zip`).
  - InnoSetup native installer configuration (`installer/castsprint_setup.iss`) with automated uninstaller and start menu shortcuts.
- [x] **Code Signing Guidance**: Ready for Authenticode EV code signing via `signtool.exe` using corporate certificate credentials in CI.

### B. macOS Desktop Receiver (`apps/macos/CastSprintMac/`)
- [x] **Native Universal / Apple Silicon Compilation**: Native SwiftPM release build with Metal shaders compiled via `metal` and `metallib`.
- [x] **High-Resolution AppIcon Set**: Generated multi-resolution `AppIcon.icns` up to 1024×1024 Retina via `iconutil`.
- [x] **Hardened Runtime & Permissions**: `CastSprintMac.entitlements` configures Hardened Runtime with standard camera/microphone permissions for USB screen capture.
- [x] **Automated Packaging Engine**: `scripts/package_macos.sh` generates standalone `CastSprint.app` and Drag-and-Drop `.dmg`.
- [x] **Verified Release Artifacts**: Generated `dist/macos/CastSprint-v0.2.0-macOS.dmg` (1.4MB) with verified SHA-256 checksum (`03cab6b...`).
- [x] **Apple Notarization Ready**: Fully documented automated `xcrun notarytool submit` and `xcrun stapler staple` workflow in `docs/apple/MAC_INSTALLATION.md`.

### C. Android Mobile Streaming Client (`apps/android/`)
- [x] **Google Play Target SDK Compliance**: Target SDK 34 / 35 (Android 14 / 15); Min SDK 29 (Android 10).
- [x] **Release Artifacts**: Release Android App Bundle (`app-release.aab`) and universal standalone APK (`app-release.apk`).
- [x] **Permissions & Policy Disclosures**: Documented in `docs/distribution/PLAY_STORE_LISTING.md`:
  - `FOREGROUND_SERVICE_MEDIA_PROJECTION` declared with explicit user consent dialog.
  - Zero sensitive background permissions (no SMS, location, or contacts).
  - Data safety disclosure: "No data collected or shared with third parties".

### D. iOS Mobile Streaming Client (`apps/ios/`)
- [x] **Dual-Engine Capture Architecture**: Modern ScreenCaptureKit engine with legacy ReplayKit Broadcast Upload Extension fallback.
- [x] **Memory Ceiling Watchdog**: Legacy broadcast extension operates strictly under 25 MB dirty memory (well below Apple's 50 MB termination limit).
- [x] **Store Metadata & Privacy Form**: Documented in `docs/apple/APP_STORE_SUBMISSION.md` and `docs/apple/APP_STORE_PRIVACY.md`:
  - Privacy Nutrition Label: "Data Not Collected".
  - App Store Review Notes with local testing instructions.
- [x] **Distribution Channels**:
  - Apple TestFlight public beta archive via Xcode Cloud / Fastlane.
  - Open-source developer sideloading via Xcode (documented in `docs/apple/IOS_INSTALLATION.md`).
