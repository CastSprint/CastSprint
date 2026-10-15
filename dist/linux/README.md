# CastSprint Linux Desktop Receiver

## Overview
The CastSprint Linux Desktop Receiver is a native C++20 Linux application engineered for ultra-low latency mobile screen mirroring over Wi-Fi and USB, delivering real-time video/audio frames for OBS Studio and desktop display.

- **Source Code Location:** [`apps/linux/`](../../apps/linux/)
- **Desktop Launcher File:** [`apps/linux/castsprint.desktop`](../../apps/linux/castsprint.desktop)
- **CI Workflow:** [`.github/workflows/linux.yml`](../../.github/workflows/linux.yml)

---

## Architecture & Subsystems

1. **Protocol V1 LAN Socket Server (`apps/linux/src/lan_server.cpp`):**
   - High-performance non-blocking POSIX socket server listening on port `27183`.
   - Protocol V1 binary packet demuxing (magic header validation, AES/GCM decryption hooks, CRC verification).
   - Generates and validates dynamic 6-digit session pairing PINs.

2. **Video Processing Pipeline (`apps/linux/src/video_decoder.cpp`):**
   - H.264 Annex-B NAL unit parser (SPS, PPS, IDR, Non-IDR).
   - Low-latency decoding engine for presentation on Wayland / X11 surfaces.

3. **Audio Playback Engine (`apps/linux/src/audio_player.cpp`):**
   - Low-latency PCM streaming engine synchronized with incoming video presentation timestamps.

4. **Desktop Integration:**
   - Standard freedesktop `.desktop` specification entry for GNOME, KDE Plasma, XFCE, and modern desktop environments.
   - High-resolution 256x256 application icon.

---

## Building from Source on Linux

### Prerequisites
- Any modern Linux distribution (Ubuntu 20.04+, Debian 11+, Fedora 36+, Arch Linux)
- GCC 11+ or Clang 14+ with C++20 support
- CMake 3.22+ and Ninja build

#### Ubuntu / Debian
```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake ninja-build pkg-config
```

#### Fedora / RHEL
```bash
sudo dnf install -y gcc-c++ cmake ninja-build
```

#### Arch Linux
```bash
sudo pacman -S base-devel cmake ninja
```

### Build Commands
```bash
# 1. Clone repository
git clone https://github.com/CastSprint/CastSprint.git
cd CastSprint

# 2. Configure CMake
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release

# 3. Build Linux Receiver
cmake --build build --target castsprint_receiver_linux --parallel

# 4. Run Smoke Test
./build/apps/linux/castsprint_receiver_linux --smoke-test

# 5. Launch Receiver
./build/apps/linux/castsprint_receiver_linux
```

### System Installation (Optional)
To install CastSprint system-wide so it appears in your application launcher menu:
```bash
sudo cmake --install build
```
This installs:
- Executable: `/usr/local/bin/castsprint_receiver_linux`
- Launcher: `/usr/local/share/applications/castsprint.desktop`
- Icon: `/usr/local/share/icons/hicolor/256x256/apps/castsprint.png`

### Packaging Release Archive
To generate the standalone tarball distribution:
```bash
bash scripts/package_linux.sh
```
Output archive will be created in `dist/linux/`:
- `CastSprint-v0.2.0-Linux-x86_64.tar.gz`
- `CastSprint-v0.2.0-Linux-x86_64.tar.gz.sha256`

---

## Continuous Integration & Automated Downloads
Every commit pushed to the repository triggers the [`.github/workflows/linux.yml`](../../.github/workflows/linux.yml) workflow on `ubuntu-latest`.

You can download the precompiled binary archive directly from the **Actions** tab on GitHub under **CastSprint-Linux-v0.2.0**.
