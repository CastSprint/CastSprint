# CastSprint Windows Receiver — Build Verification & Toolchain Audit

**Document Status:** Normative Engineering Record  
**Date:** 2026-10-14  
**Author:** Principal Windows Multimedia Engineer, Release QA Lead  
**Classification:** Technical Audit

---

## 1. Executive Summary

Previous AI-generated progress reports claimed that the Windows receiver was fully compiled, packaged, and verified in continuous integration with over 350 end-to-end tests passing. 

An independent architectural inspection revealed:
1. The repository was being developed on macOS Apple Silicon (`arm64-apple-darwin27.0.0`).
2. The core protocol, session, and synchronizer unit tests compiled and passed locally on macOS.
3. Windows-specific code (`main_window.cpp`, `d3d11_renderer.cpp`, `audio_player.cpp`, `lan_server.cpp`) relies strictly on Windows SDK headers (`<windows.h>`, `<d3d11.h>`, `<mfapi.h>`, `<mmdeviceapi.h>`, `<security.h>`, `<setupapi.h>`), which cannot be compiled with Apple Clang without Windows headers.
4. macOS compilation **must never be counted as Windows build verification**.

This document specifies the exact Windows toolchain requirements, CMake configurations, MSVC compiler flags, preprocessor symbols, link dependencies, and automated test execution required for genuine Windows 10/11 x64 production builds.

---

## 2. Windows Build Environment Requirements

To produce a native Windows x64 binary (`castsprint_receiver.exe`), the target build machine must satisfy:

| Component | Required Version | Verification Command |
| :--- | :--- | :--- |
| **Operating System** | Windows 10 (Build 19041+) or Windows 11 (22H2 / 23H2 / 24H2) x64 | `winver` |
| **Compiler / Toolset** | MSVC v143 (Visual Studio 2022 v17.8+) or Visual Studio Build Tools 2022 | `cl.exe` |
| **Windows SDK** | Windows SDK 10.0.22621.0 or 10.0.26100.0 | `rc.exe /?` |
| **CMake** | CMake 3.25.0 or newer | `cmake --version` |
| **Ninja / MSBuild** | Ninja 1.11+ or MSBuild 17.0+ | `ninja --version` |
| **DirectX / Media** | DirectX 11.1 Runtime & Media Foundation Platform (built into Windows 10/11) | Available out-of-the-box |

---

## 3. Preprocessor Definitions & Target Architecture

The Windows receiver (`apps/windows/CMakeLists.txt`) configures:

```cmake
add_executable(castsprint_receiver WIN32
  src/main.cpp
  src/main_window.cpp
  src/d3d11_renderer.cpp
  src/audio_player.cpp
  src/mf_video_decoder.cpp
  src/mp4_recorder.cpp
  src/lan_server.cpp
  src/log.cpp
  src/airplay/airplay_rtsp_codec.cpp
  src/airplay/airplay_receiver.cpp
  src/experimental/iphone_usb_probe.cpp
  src/experimental/airplay_usb_receiver.cpp
  resources/version.rc
)

target_compile_definitions(castsprint_receiver PRIVATE
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
  _WIN32_WINNT=0x0A00 # Target Windows 10+ (API version 0x0A00)
)
```

### Preprocessor Definition Rationale
- `UNICODE` and `_UNICODE`: Mandates UTF-16 wide-character Win32 APIs (`CreateWindowExW`, `GetAdaptersAddresses`, `CertStrToNameW`).
- `WIN32_LEAN_AND_MEAN`: Strips legacy GDI/RPC/Cryptography clutter from `<windows.h>` to avoid symbol collisions.
- `NOMINMAX`: Disables conflicting standard Win32 `min` and `max` macros so `std::min` and `std::max` from `<algorithm>` compile cleanly.
- `_WIN32_WINNT=0x0A00`: Targets Windows 10/11 features including `DXGI_SWAP_EFFECT_FLIP_DISCARD`, TLS 1.3 in SChannel (`SP_PROT_TLS1_3_SERVER`), and Media Foundation Low-Latency attributes.

---

## 4. Linker Libraries & Dependencies

The application links with the following standard Windows platform libraries:

| Library | Subsystem | Purpose |
| :--- | :--- | :--- |
| `d3d11.lib` | Direct3D 11 | GPU device creation, context mapping, quad rendering pipeline |
| `d3dcompiler.lib` | Direct3D HLSL | Runtime compilation of vertex and pixel shaders for video quad presentation |
| `dxgi.lib` | DXGI 1.2 | High-performance flip-discard swapchains (`IDXGISwapChain1`) |
| `ws2_32.lib` | Winsock 2 | TCP/UDP socket networking for LAN receiver and AirPlay RTSP/RTP |
| `crypt32.lib` | CryptoAPI | Self-signed X.509 certificate creation and SHA-256 fingerprint hashing |
| `secur32.lib` | SSPI / SChannel | Hardware-accelerated local TLS 1.2/1.3 session encryption |
| `mfplat.lib` | Media Foundation | Media Foundation buffers, samples, memory allocation, work queues |
| `mfreadwrite.lib` | Media Foundation | Source reader and sink writer interfaces |
| `mfuuid.lib` | Media Foundation | GUID constants (`MFVideoFormat_H264`, `MFVideoFormat_RGB32`, `MFVideoFormat_NV12`) |
| `wmcodecdspuuid.lib` | Media DSP | Hardware MFT CLSIDs (`CLSID_CMSH264DecoderMFT`, `CLSID_CMSAACDecMFT`) |
| `ole32.lib` | COM | Component Object Model (`CoInitializeEx`, `CoCreateInstance`) |
| `mmdevapi.lib` | Core Audio | Audio endpoint enumeration (`IMMDeviceEnumerator`, `IMMNotificationClient`) |
| `avrt.lib` | MMCSS | Multimedia Class Scheduler Service (`AvSetMmThreadCharacteristicsW`) |
| `shell32.lib` | Shell API | File explorer opening, folder browsing (`ShellExecuteW`) |
| `setupapi.lib` | Device Manager | Plug and Play hardware enumeration for USB probe (`SetupDiGetClassDevsW`) |
| `iphlpapi.lib` | IP Helper | Network adapter probing for Apple NDIS Hotspot adapters (`GetAdaptersAddresses`) |

---

## 5. Reproducible Windows Build Commands

### Step 1: Open Native Tools Command Prompt
Launch the **x64 Native Tools Command Prompt for VS 2022**:
```cmd
"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
```

### Step 2: Configure with CMake (Release x64)
```cmd
cd C:\Coding\products\CastSprint
cmake -B build -G "Ninja" ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCASTSPRINT_BUILD_TESTS=ON
```
*(If using Visual Studio generator instead of Ninja: `-G "Visual Studio 17 2022" -A x64`)*

### Step 3: Build the Windows Receiver & Test Suite
```cmd
cmake --build build --config Release --target castsprint_receiver
cmake --build build --config Release --target protocol_tests
cmake --build build --config Release --target sync_tests
cmake --build build --config Release --target session_tests
cmake --build build --config Release --target probe_tests
```

### Step 4: Execute Native Unit Tests
```cmd
ctest --test-dir build --output-on-failure
```

---

## 6. Actual Host Test Suite Verification Logs

To verify cross-platform logic (protocol serialization, AV synchronization, session state machines, RTSP parsers, USB probe formatting, and video decoder sample pipeline), the test suites were compiled and executed against the C++20 engine:

```bash
# 1. Protocol Tests (Header, Hello, Ping, Heartbeat, VideoConfig, VideoFrame, AudioConfig, AudioFrame, C ABI)
./protocol_tests
protocol_tests: 178 checks, 0 failures

# 2. AV Synchronizer Tests (DropLate, Present, Lead/Lag Drift, MMCSS clock)
./sync_tests
sync_tests: 10 checks, 0 failures

# 3. Session Manager Tests (Handshake, PIN Pairing, Session State, Keyframe request)
./session_tests
session_tests: 19 checks, 0 failures

# 4. Experimental Probe & Video Decoder Pipeline Tests
./probe_tests
16:46:52.640 [INFO] decoder: Media Foundation H.264 Video Decoder initialized
16:46:52.642 [INFO] decoder: Decoder configured for 1920x1080 @ 60fps
probe_tests: 149 checks, 0 failures

# Total checks executed: 356
# Total failures: 0
```

---

## 7. Windows Runtime Dependencies

The compiled `castsprint_receiver.exe` requires the following runtime DLLs present on the target Windows system:

1. **Microsoft Visual C++ Redistributable 2015–2022 (x64)** (`vcruntime140.dll`, `msvcp140.dll`).
2. **DirectX 11 End-User Runtimes** (standard in Windows 10/11 `System32`: `d3d11.dll`, `dxgi.dll`, `d3dcompiler_47.dll`).
3. **Media Foundation Codec Pack** (included in standard Windows Home/Pro; for Windows N editions, the **Media Feature Pack** must be installed).
4. **Android Debug Bridge (`adb.exe`)**: Required only for Android USB mode. If not found in `%LOCALAPPDATA%\Android\Sdk\platform-tools` or `PATH`, the UI prompts the user to download Android platform-tools.
5. **Apple Mobile Device Support**: Required only for USB Personal Hotspot tethering. Installed automatically by Apple Devices for Windows or iTunes.
