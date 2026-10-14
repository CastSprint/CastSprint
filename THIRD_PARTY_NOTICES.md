# Third-Party Software Notices and Licenses

CastSprint is an original, open-source project distributed under the [Apache License, Version 2.0](LICENSE). 
This file documents all third-party libraries, toolchains, and operating system interfaces utilized by CastSprint across its supported platforms.

---

## 1. Overview of Included & Linked Dependencies

CastSprint is engineered with an ultra-lean dependency profile to prevent supply-chain vulnerabilities, licensing contamination, and binary bloat:

- **Zero GPL / LGPL Copyleft Contamination:** CastSprint does not link against GPL or LGPL libraries (such as `ffmpeg`, `libusb-1.0`, or `libimobiledevice`).
- **No Embedded Third-Party Binaries:** All video and audio compression/decompression uses standard, hardware-accelerated operating system APIs (`MediaCodec` on Android, `VideoToolbox` & `CoreAudio` on Apple platforms, `Direct3D 11` & `Media Foundation` on Windows).
- **No Analytics / Advertising SDKs:** CastSprint contains no third-party telemetry, crash reporters, tracking pixels, or monetization libraries.

---

## 2. Component Audits by Platform

### A. Android Application (`apps/android`)
* **Kotlin Standard Library & Coroutines:**
  - Copyright: © JetBrains s.r.o. and Kotlin Programming Language contributors.
  - License: Apache License 2.0.
  - Link: https://github.com/JetBrains/kotlin
* **AndroidX Libraries (Core, Appcompat, Material Design, Activity-KTX):**
  - Copyright: © The Android Open Source Project.
  - License: Apache License 2.0.
  - Link: https://source.android.com
* **Android Gradle Plugin (AGP) & Gradle Toolchain:**
  - Build-time only dependencies; not distributed in the final APK artifact.
  - License: Apache License 2.0.
* **JUnit 4 (Test Only):**
  - Used strictly for offline unit tests (`ProtocolCodecTest`, etc.).
  - License: Eclipse Public License 1.0 (EPL-1.0).

### B. Apple macOS & iOS Applications (`apps/macos`, `apps/ios`)
* **Swift Standard Library & Runtime:**
  - Copyright: © Apple Inc. and the Swift project authors.
  - License: Apache License 2.0 with Runtime Library Exception.
  - Link: https://swift.org/LICENSE.txt
* **Operating System Frameworks (Dynamically Linked System APIs):**
  - `AVFoundation.framework`, `CoreMediaIO.framework`, `CoreMedia.framework`, `VideoToolbox.framework`, `CoreAudio.framework`, `Metal.framework`, `MetalKit.framework`, `Network.framework`, `ReplayKit.framework`, `ScreenCaptureKit.framework`, `SwiftUI.framework`, `AppKit.framework`.
  - Provided directly by macOS and iOS operating systems; no third-party redistributables.
* **Android Debug Bridge (`adb` client wrapper in `ADBDeviceManager.swift`):**
  - Invokes system/user-installed `adb` binary over process pipe (`/opt/homebrew/bin/adb`, Android SDK platform-tools).
  - License: Apache License 2.0 (Google AOSP).

### C. Windows Desktop Application (`apps/windows`)
* **Microsoft Windows System Libraries (Dynamically Linked OS APIs):**
  - `d3d11.lib`, `dxgi.lib`, `ws2_32.lib`, `crypt32.lib`, `secur32.lib`, `mfplat.lib`, `mfreadwrite.lib`, `mmdevapi.lib`, `setupapi.lib`.
  - Provided by Microsoft Windows 10/11 operating system under standard Windows End User License Agreement.
* **DirectX / Direct3D 11 Shader Compiler:**
  - Compiles standard HLSL shaders into DXBC byte code; uses built-in Windows runtime compiler.

### D. Shared Native C++ Code (`native/protocol`, `native/sync`, `native/session`)
* **CastSprint Protocol v1 (`native/protocol`):**
  - Original C++20 protocol codec developed specifically for CastSprint.
  - Copyright: © 2026 The CastSprint Project Authors.
  - License: Apache License 2.0.
* **Audio/Video Synchronizer (`native/sync`):**
  - Original implementation of low-latency presentation timestamp drift compensation.
  - Copyright: © 2026 The CastSprint Project Authors.
  - License: Apache License 2.0.
* **Session & Security Manager (`native/session`):**
  - Original implementation of PIN authentication, rolling statistics, and heartbeat RTT tracking.
  - Copyright: © 2026 The CastSprint Project Authors.
  - License: Apache License 2.0.

---

## 3. Patent & Codec Notice

CastSprint relies exclusively on operating system hardware decoders and encoders (such as Apple VideoToolbox, Android MediaCodec, and Windows Media Foundation) to process H.264 (AVC) and H.265 (HEVC) video, and AAC-LC audio streams. 

CastSprint does not redistribute, bundle, or compile independent software implementations of H.264 or HEVC codecs. Licensing for hardware codec encoding and decoding is provided through the respective operating system vendor (Apple, Google, Microsoft) and device hardware manufacturer.
