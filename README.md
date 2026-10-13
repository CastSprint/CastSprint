# CastSprint

<p align="center">
  <img src="apps/android/app/src/main/res/drawable/castsprint_logo.png" alt="CastSprint Logo" width="128" height="128" />
  <br>
  <strong>High-Performance, Low-Latency Android Screen & Audio Mirroring for Mobile Gamers & Streamers</strong>
  <br>
  <em>100% Free Forever · No Paywalls · No Ads · No Watermarks · No Cloud Required</em>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#key-features">Key Features</a> •
  <a href="#obs-integration">OBS Integration</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#documentation">Documentation</a> •
  <a href="#building-from-source">Building</a> •
  <a href="#privacy--license">Privacy</a>
</p>

---

## Overview

**CastSprint** is a native, ultra-low-latency screen and game audio mirroring system designed specifically for competitive mobile gamers, esports content creators, and livestreamers. It connects an Android phone (Android 10+) directly to a Windows PC (Windows 10/11 x64) over high-speed USB or encrypted local Wi-Fi without any third-party cloud servers or account sign-ups.

### The CastSprint Promise
- **Free Forever**: Every feature—including 60 FPS, 1080p+, internal game audio, and MP4 recording—is completely free. There are no "Pro" tiers, timed limits, or in-app purchases.
- **Zero Watermarks & Zero Ads**: Your stream stays 100% clean and uncompromised.
- **100% Local & Private**: Direct USB (`adb reverse`) or local TLS 1.3 Wi-Fi connection. No data ever leaves your local network.

---

## Key Features

- **⚡ Sub-40ms End-to-End Latency**: Hardware-accelerated H.264 encode via Android `MediaCodec` direct surface capture and Direct3D 11 flip-model hardware presentation on Windows.
- **🔊 Pure Internal Game Audio**: Crystal-clear 48 kHz stereo AAC audio captured directly from Android games via `AudioPlaybackCapture` (no microphone recording or background noise).
- **⏱️ Hardware AV Synchronization**: Proprietary monotonic clock alignment and regression synchronizer ensures audio and video never drift out of sync during long gaming sessions.
- **📹 Direct-to-Disk MP4 Recording**: Zero-transcoding local recording. Direct3D and Media Foundation Sink Writer stream incoming H.264 and AAC packets directly to standard MP4 files without GPU/CPU re-encoding penalties.
- **🌐 Dual Connection Modes**:
  - **USB Mode**: Plug-and-play tethering via ADB reverse socket forwarding for tournament-grade latency (<35 ms).
  - **Wi-Fi Mode**: Zero-cable local LAN streaming with mDNS discovery, TLS 1.3 certificate pinning, and PIN authentication.
- **🎮 Gaming-Grade Windows Receiver UI**: Native C++20 Win32 application with a modern dark gaming aesthetic, 6 interactive screens, real-time diagnostic HUD, and borderless fullscreen (`F11`).
- **🎬 Native OBS Studio Optimization**: Flip-model DXGI swapchain built specifically for zero-overhead Windows Graphics Capture (WGC) in OBS Studio.

---

## Quick Start

### 1. USB Connection (Recommended for Lowest Latency)
1. **Enable USB Debugging** on your Android device (`Settings` → `Developer options` → `USB debugging`).
2. **Connect your phone** to your PC with a high-quality USB-C cable and accept the RSA prompt.
3. **Launch CastSprint** on Windows. The app automatically exposes the port via `adb reverse tcp:8080 tcp:8080`.
4. **Open CastSprint on Android**, choose a preset (e.g., **Balanced: 1080p 60fps**), and tap **Start Mirroring**.
5. *For detailed steps, see [USB Connection Guide](docs/USB_CONNECTION.md).*

### 2. Wi-Fi Connection (Zero Cables)
1. Ensure both your phone and PC are connected to the same Wi-Fi network (5 GHz Wi-Fi 6 or 5 recommended).
2. Open CastSprint on Windows and navigate to the **Home** screen to view your local IP and 4-digit pairing PIN.
3. Open CastSprint on Android, select **Wi-Fi Mode**, tap **Pair / Discover**, and select your PC (or enter IP manually).
4. Enter the PIN and tap **Start Mirroring**.
5. *For firewall rules and pairing troubleshooting, see [Wi-Fi Connection Guide](docs/WIFI_CONNECTION.md).*

---

## OBS Integration

CastSprint is designed from the ground up for live streamers using **OBS Studio**:

```
+------------------------------------+
|  Android Device (Game + Audio)     |
+-----------------+------------------+
                  |  USB / TLS LAN (CSP1 Protocol)
                  v
+-----------------+------------------+
|  CastSprint Windows Receiver       |
|  - D3D11 Flip-Discard Swapchain    |
|  - WASAPI Shared Audio Output      |
+-----------------+------------------+
                  |  Windows Graphics Capture (WGC)
                  v
+-----------------+------------------+
|  OBS Studio Scene                  |
|  - Window Capture (Zero Copy)      |
|  - Application Audio Capture       |
+------------------------------------+
```

1. In OBS Studio, add a **Window Capture** source to your gaming scene.
2. Select `[CastSprint.exe]: CastSprint — Gaming Screen Mirroring`.
3. Set **Capture Method** to `Windows 10 (1903 and up)` (WGC). This enables zero-copy hardware capture of the Direct3D 11 flip-model swapchain.
4. Add an **Application Audio Capture (BETA)** source and select CastSprint to isolate game audio from Discord or music.
5. *Read the full walkthrough in the [OBS Studio Streaming Guide](docs/OBS_GUIDE.md).*

---

## Windows Application Shortcuts

| Hotkey | Action |
|:---:|:---|
| <kbd>F11</kbd> | Toggle Borderless Fullscreen Gaming View |
| <kbd>1</kbd> – <kbd>6</kbd> | Switch Screens (1: Home, 2: Gaming, 3: Stream, 4: Record, 5: Perf, 6: Settings) |
| <kbd>R</kbd> | Start / Stop MP4 Recording |
| <kbd>M</kbd> | Toggle Audio Mute |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Volume Up / Down (5% increments) |
| <kbd>[</kbd> / <kbd>]</kbd> | Calibrate Audio Sync Offset (-10 ms / +10 ms) |
| <kbd>Esc</kbd> | Exit Fullscreen Mode |

---

## Performance Targets

| Metric | USB 3.0 / 2.0 | 5 GHz Wi-Fi 6 |
|:---|:---:|:---:|
| **Glass-to-Glass Latency** | 28 – 38 ms | 45 – 65 ms |
| **Max Frame Rate** | 60 FPS (120 FPS capable) | 60 FPS |
| **Resolution** | Up to Native (1080p, 1440p) | 720p / 1080p |
| **Audio Latency** | < 25 ms | < 35 ms |
| **Audio/Video Drift** | < 5 ms | < 10 ms |
| **PC CPU Usage** | < 1.5% (Ryzen 5 / i5) | < 2.0% |

*For complete benchmark methodology and high-speed camera validation, see [Performance & Latency Profiling](docs/PERFORMANCE.md).*

---

## Documentation

- **Setup & Connectivity**:
  - [USB Connection & Driver Guide](docs/USB_CONNECTION.md)
  - [Local Wi-Fi Pairing & TLS Security](docs/WIFI_CONNECTION.md)
  - [OBS Studio Livestreaming Guide](docs/OBS_GUIDE.md)
  - [Comprehensive Troubleshooting Matrix](docs/TROUBLESHOOTING.md)
- **Technical Architecture**:
  - [Architecture Overview](docs/architecture/OVERVIEW.md)
  - [Streaming Pipeline](docs/architecture/STREAMING_PIPELINE.md)
  - [CastSprint Protocol v1 Specification](docs/architecture/PROTOCOL.md)
  - [Threading & Memory Safety](docs/architecture/THREADING.md)
  - [Security & TLS Pinning](docs/architecture/SECURITY.md)
- **Quality & Release**:
  - [Performance & Latency Profiling](docs/PERFORMANCE.md)
  - [Privacy & Free Forever Statement](docs/PRIVACY.md)
  - [Release Checklist](docs/RELEASE_CHECKLIST.md)
  - [Development Progress Log](docs/PROGRESS.md)

---

## Building from Source

### Prerequisites
- **Host / Protocol / Tests**: CMake 3.22+, modern C++20 compiler (MSVC 2022, Clang 15+, or GCC 12+).
- **Android App**: Android Studio Ladybug / Koala, JDK 17, Android SDK Platform 34/35.
- **Windows App**: Visual Studio 2022 (v143 toolset), Windows 10/11 SDK (Direct3D 11, Media Foundation).

### Building Host Tests (macOS / Linux / Windows)
```bash
cmake -S . -B build/host
cmake --build build/host
ctest --test-dir build/host --output-on-failure
```

### Building Android Client
```bash
cd apps/android
./gradlew assembleDebug testDebugUnitTest
# Output APK: apps/android/app/build/outputs/apk/debug/app-debug.apk
```

### Building Windows Receiver & Installer
```bash
cmake -S . -B build/win -G "Visual Studio 17 2022" -A x64
cmake --build build/win --config Release

# Package Windows Installer (requires Inno Setup 6):
iscc installer/castsprint_installer.iss
# Output: installer/Output/CastSprint-Setup-0.2.0-beta.exe
```

---

## Privacy & License

CastSprint is built on the philosophy that streaming tools should be **transparent, secure, and private**:
- **No telemetry, analytics, or user profiling**.
- **No microphones tapped** (internal audio only).
- **No internet access required** (works entirely on offline USB or local subnet).

Read the complete pledge at [docs/PRIVACY.md](docs/PRIVACY.md).
Licensed under Apache 2.0 (see [docs/development/LICENSING.md](docs/development/LICENSING.md)).
