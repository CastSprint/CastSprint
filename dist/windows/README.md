# CastSprint Windows Desktop Receiver

## Overview
The CastSprint Windows Desktop Receiver is a native C++20 Win32 application engineered for ultra-low latency mobile screen mirroring, high-framerate gameplay preview (Direct3D 11), synchronous audio playback (WASAPI), and OBS Studio livestreaming integration.

- **Source Code Location:** [`apps/windows/`](../../apps/windows/)
- **Installer Script:** [`installer/castsprint_installer.iss`](../../installer/castsprint_installer.iss)
- **CI Workflow:** [`.github/workflows/windows.yml`](../../.github/workflows/windows.yml)

---

## Architecture & Subsystems

1. **Direct3D 11 Renderer (`apps/windows/src/d3d11_renderer.cpp`):**
   - Direct hardware presentation via DXGI swapchain.
   - Zero-copy NV12 / YUV420p shader pipeline with BT.709 color conversion.
   - Seamless borderless fullscreen toggle (`F11`) with auto-hiding controls for clean OBS window capture.

2. **Hardware Video Decoder (`apps/windows/src/mf_video_decoder.cpp`):**
   - Microsoft Media Foundation H.264 Transform (MFT).
   - Real-time SPS/PPS parameter set extraction and low-latency frame decoding.

3. **WASAPI Audio Engine (`apps/windows/src/audio_player.cpp`):**
   - Shared-mode Windows Audio Session API with low-latency event-driven buffers.
   - Automatic 48 kHz / 44.1 kHz PCM resampling.

4. **Network & Protocol Engine (`apps/windows/src/lan_server.cpp`):**
   - Winsock TCP socket listening on default port `27183`.
   - Protocol V1 binary packet demuxing with session PIN authentication.

5. **USB ADB Tunneling (`apps/windows/src/adb_tunnel.hpp`):**
   - Automated ADB device detection and `adb reverse tcp:27183 tcp:27183` forwarder for Android USB tethered streaming.

---

## Building from Source on Windows

### Prerequisites
- Windows 10 (version 19041+) or Windows 11 x64
- Visual Studio 2022 (v17.0+) with "Desktop development with C++" workload
- CMake 3.22+
- *(Optional)* Inno Setup 6 to compile the installer

### Build Commands
Open **Developer Command Prompt for VS 2022** or **PowerShell**:

```cmd
# 1. Clone repository
git clone https://github.com/CastSprint/CastSprint.git
cd CastSprint

# 2. Configure CMake
cmake -S . -B build -G "Visual Studio 17 2022" -A x64

# 3. Build in Release mode
cmake --build build --config Release --target castsprint_receiver --parallel

# 4. Run the executable
.\build\apps\windows\Release\castsprint_receiver.exe
```

### Packaging
To generate the portable release ZIP and Inno Setup installer executable:
```cmd
scripts\package_windows.bat
```
Output files will be generated in `dist\windows\`:
- `CastSprint-v0.2.0-Windows-x64.zip` (Portable executable + docs)
- `CastSprint_Setup_v0.2.0_Beta_x64.exe` (Windows Installer)

---

## Continuous Integration & Automated Downloads
Every commit pushed to the repository triggers the [`.github/workflows/windows.yml`](../../.github/workflows/windows.yml) workflow on a native `windows-latest` runner.

You can download the precompiled binary directly from the **Actions** tab on GitHub under **CastSprint-Windows-v0.2.0**.
