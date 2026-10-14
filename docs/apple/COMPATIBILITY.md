# CastSprint — Master Device & Platform Compatibility Guide

**Release Version:** 0.2.0 (Public Beta)  
**Document Classification:** Official Platform Support Specification  

---

## 1. Master Compatibility Matrix

| Mobile Device Source | Host Computer Receiver | Connection Type | Mobile App Required? | Support Status | Typical Latency | Supported Audio |
|:---|:---|:---:|:---:|:---:|:---:|:---:|
| **iPhone (USB-C / Lightning)** | **Apple Mac (macOS 14+)** | **Physical USB** | **NO (Zero App)** | **Production Ready** | **12 – 18 ms** | Uncompressed Digital Stereo |
| **iPad / iPad Pro** | **Apple Mac (macOS 14+)** | **Physical USB** | **NO (Zero App)** | **Production Ready** | **12 – 18 ms** | Uncompressed Digital Stereo |
| **Android Phone / Tablet** | **Apple Mac (macOS 14+)** | **USB (ADB)** | Yes (CastSprint Android) | **Production Ready** | **25 – 35 ms** | 48kHz Internal Game Audio |
| **Android Phone / Tablet** | **Apple Mac (macOS 14+)** | **Wi-Fi (LAN)** | Yes (CastSprint Android) | **Production Ready** | **45 – 65 ms** | 48kHz Internal Game Audio |
| **iPhone / iPad** | **Apple Mac (macOS 14+)** | **Wi-Fi (LAN)** | Yes (CastSprint iOS) | **Production Ready** | **40 – 60 ms** | 48kHz AAC-LC Game Audio |
| **Android Phone / Tablet** | **Windows PC (Win 10/11)** | **Physical USB** | Yes (CastSprint Android) | **Production Ready** | **25 – 35 ms** | WASAPI 48kHz Game Audio |
| **Android Phone / Tablet** | **Windows PC (Win 10/11)** | **Wi-Fi (LAN)** | Yes (CastSprint Android) | **Production Ready** | **45 – 65 ms** | WASAPI 48kHz Game Audio |
| **iPhone / iPad** | **Windows PC (Win 10/11)** | **Wi-Fi (LAN)** | Yes (CastSprint iOS) | **Production Ready** | **40 – 60 ms** | WASAPI 48kHz Game Audio |
| **iPhone / iPad** | **Windows PC (Win 10/11)** | **Physical USB** | — | **Unsupported (No-Go)** | N/A | N/A (See Research Report) |

---

## 2. Hardware and Operating System Requirements

### A. Apple Mac Receiver (Desktop Host)
* **Supported OS:** macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia).
* **Hardware Architecture:**
  * Apple Silicon: M1, M2, M3, M4 (Pro, Max, Ultra) — Native ARM64.
  * Intel Core: Core i5, i7, i9 (x86_64) with Metal 2/3 GPU support.
* **Ports & Cables:** Standard USB-C to USB-C or USB-A to Lightning cable.
* **Permissions:** Camera (for external USB video input) and Microphone (for USB audio).

### B. Windows PC Receiver (Desktop Host)
* **Supported OS:** Windows 10 (version 1903+) or Windows 11 (64-bit).
* **Graphics Hardware:** Direct3D 11 feature level 11_0+ (Intel UHD 620+, NVIDIA GTX 900+, AMD Radeon RX 400+).
* **Audio Engine:** Windows Audio Session API (WASAPI) shared mode.
* **Network:** Local Wi-Fi connection with TCP port `27183` unblocked by Windows Firewall.

### C. iPhone & iPad (Mobile Capture Senders)
* **Supported OS:** iOS 15.0 through iOS 18.x / iPadOS 15.0 through iPadOS 18.x.
* **Supported Devices:**
  * iPhone: iPhone 8, iPhone X, iPhone 11, 12, 13, 14, 15, 16 (all variants).
  * iPad: iPad (6th gen+), iPad mini (5th gen+), iPad Air (3rd gen+), iPad Pro (all models).
* **Connector Support:**
  * Lightning devices (USB 2.0 480 Mbps): Fully supported for both USB to Mac and Wi-Fi streaming.
  * USB-C devices (USB 2.0 / USB 3.2 10 Gbps / Thunderbolt): Native high-speed capture.

### D. Android Devices (Mobile Capture Senders)
* **Supported OS:** Android 10 (API 29) through Android 15/16 (API 36).
* **Hardware:** Any device with a hardware H.264 encoder (`MediaCodec`).
* **Audio:** Android 10+ is mandatory for internal game audio capture (`AudioPlaybackCapture`).

---

## 3. Supported and Unsupported Scenarios

### Supported:
- Fullscreen and windowed mobile gameplay mirroring at up to 60.0 FPS.
- Native device rotation: Portrait and landscape dynamically adapt in real time.
- Direct OBS Studio Window Capture without watermarks or forced overlays.
- Simultaneous gameplay viewing and zero-transcode MP4 recording.
- Multi-hour continuous streaming sessions with zero memory leaks.

### Documented Technical Boundaries (Unsupported by Design):
1. **DRM Protected Content (HDCP / FairPlay):**
   * Video from Netflix, Disney+, Apple TV+, Amazon Prime Video, and protected cable apps cannot be captured. Operating system DRM blanks out video frames at the hardware level.
2. **Windows App-less iPhone USB Mirroring:**
   * Formally evaluated as infeasible due to lack of Apple Windows drivers and DMCA anti-circumvention constraints (detailed in [`docs/research/IPHONE_WINDOWS_USB.md`](../research/IPHONE_WINDOWS_USB.md)). Use the CastSprint iOS app over Wi-Fi.
3. **Legacy iOS Below iOS 15:**
   * Devices running iOS 14 or earlier lack modern Swift concurrency and Network.framework features and are not supported for Wi-Fi streaming.
