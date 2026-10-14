# CastSprint Windows: OBS Studio Guide for iPhone & iPad Mirroring

**Document ID:** CSR-WIN-OBS-IPHONE-01  
**Classification:** Streaming Engineering & Creator Integration  
**Author:** Principal Windows C++ Systems Engineer, Apple Interoperability Researcher, CastSprint Project  
**Date:** 2026-10-14  

---

## Executive Summary

CastSprint for Windows provides ultra-low latency, app-less iPhone and iPad screen and game audio mirroring designed specifically for creators, esports players, and livestreamers using **OBS Studio**.

### Core Creator Guarantees
1. **Completely Free Forever**: Zero watermarks, zero subscription prompts, zero time limits.
2. **Stable Native Win32 Window**: Direct3D 11 flip-model swapchain (`DXGI_SWAP_EFFECT_FLIP_DISCARD`) fully compatible with OBS Windows Graphics Capture (WGC).
3. **Discrete Game Audio Routing**: Real-time WASAPI audio output allowing isolated stream audio without capturing Discord, Spotify, or Windows desktop notification chimes.
4. **No Third-Party OBS Plugin Needed**: Uses OBS Studio's native **Window Capture** and **Application Audio Capture**, avoiding unstable third-party plugins.
5. **No Mandatory iOS Companion App**: Supports native iOS Control Center Screen Mirroring out-of-the-box.

---

## 1. Prerequisites

- **Host PC**: Windows 10 (version 1903+) or Windows 11 64-bit.
- **OBS Studio**: Version 29.0 or higher (64-bit recommended).
- **CastSprint Windows**: v0.2.0-beta or later with Direct3D 11 hardware acceleration.
- **iOS Device**: Any iPhone or iPad running iOS 14.0 or newer.
- **Connection Method**:
  - **Wired (Lowest Latency, ~24ms)**: Lightning or USB-C to USB cable with Personal Hotspot toggled to "USB Only".
  - **Wireless (Cable-Free, ~48ms)**: 5GHz local Wi-Fi router connecting PC and iPhone to the same subnet.

---

## 2. Setting Up CastSprint for Windows

### Step 1: Launch CastSprint Desktop
1. Open `castsprint_receiver.exe`.
2. On the **Home** tab, select **[ 🍎 iPhone / iPad ]**.
3. Choose your preferred connection mode:
   - **📶 AirPlay Wi-Fi**: Zero-app wireless mirroring.
   - **⚡ USB Hotspot (Wired)**: Zero-app high-speed wired mirroring (~24ms latency).
   - **🎮 CastSprint iOS App**: High-performance streaming using the dedicated Swift client.
4. Verify the AirPlay Receiver status shows **`● ACTIVE (Ready for iOS Mirroring)`**.
   - Receiver Name: **`CastSprint Desktop`**
   - RTSP Port: `7000` (TCP), RTP Port: `7010` (UDP).

### Step 2: Connect Your iPhone or iPad
- **For AirPlay Wi-Fi Mode**:
  1. Connect PC and iPhone to the same Wi-Fi network.
  2. On iPhone, swipe down from the top-right corner to open **Control Center**.
  3. Tap **Screen Mirroring** (two overlapping rectangles).
  4. Tap **CastSprint Desktop**.
- **For AirPlay USB Hotspot Mode (Recommended for Gaming)**:
  1. Connect iPhone to PC with the USB cable.
  2. Tap **Trust This Computer** on the iPhone and enter your passcode.
  3. Go to iOS **Settings > Personal Hotspot** and turn it **ON** (select *USB Only*).
  4. Open **Control Center > Screen Mirroring > CastSprint Desktop**.
  5. The stream routes across the physical USB wire via the signed `Apple Mobile Device Ethernet` adapter.

---

## 3. Configuring OBS Studio: Video Capture

### Step 1: Add a Window Capture Source
1. In OBS Studio, open your gaming scene.
2. In the **Sources** dock, click the **`+`** (Add) button.
3. Select **Window Capture** and name it `iPhone Gameplay`.

### Step 2: Configure Window Capture Properties
Set the following properties in the dialog:
- **Window**: Select `[castsprint_receiver.exe]: CastSprint — Gaming View` (or `[castsprint_receiver.exe]: CastSprint`).
- **Capture Method**: Select **`Windows 10 (1903 and up)`**.
  > [!IMPORTANT]
  > Using the modern **Windows Graphics Capture (WGC)** method enables direct zero-copy GPU memory sharing from CastSprint's Direct3D 11 swapchain into OBS. This ensures zero tearing, smooth 60 FPS pacing, and bypasses Windows DWM compositing overhead.
- **Window Match Priority**: `Match title, otherwise find window of same executable`.
- **Capture Cursor**: **Unchecked** (prevents PC mouse pointer from showing over mobile touch games).
- **Client Area**: Checked.

### Step 3: Aspect Ratio & Canvas Alignment
Modern iPhones use an ultrawide aspect ratio (~19.5:9, e.g., 2556×1179 or 2796×1290):
- **Landscape Games** (e.g., *Call of Duty: Mobile*, *PUBG Mobile*, *Genshin Impact*):
  - In OBS, right-click the `iPhone Gameplay` source $\rightarrow$ **Transform** $\rightarrow$ **Fit to screen** (`Ctrl+F`).
  - To eliminate horizontal black letterboxes on a standard 16:9 canvas (1920×1080), you can scale or position your webcam, stream chat, and overlays in the unused margins.
- **Portrait Games** (e.g., *Clash Royale*, *Subway Surfers*, *TikTok*):
  - In OBS, right-click the source $\rightarrow$ **Transform** $\rightarrow$ **Center on screen**.
  - Portrait orientation preserves true pixel aspect ratio without stretching or distortion.

### Step 4: Hide Controls in OBS
- In CastSprint, switch to the **[2] Gaming View** tab or press **`F11`** to enter borderless fullscreen.
- In Gaming View, CastSprint hides all navigation headers, sidebars, and diagnostic controls, presenting only the clean mobile video stream for OBS capture.

---

## 4. Configuring OBS Studio: Discrete Game Audio Capture

CastSprint renders mobile game audio in 48kHz 16-bit stereo using Windows **WASAPI** shared-mode.

### Recommended Method: Application Audio Capture (BETA / Native in OBS 28+)
This method isolates your iPhone game audio directly from the `castsprint_receiver.exe` process:
1. In OBS Studio, under **Sources**, click **`+`**.
2. Select **Application Audio Capture (BETA)** and name it `iPhone Game Audio`.
3. In the properties window:
   - **Mode**: `Capture specific window`.
   - **Window**: Select `[castsprint_receiver.exe]: CastSprint`.
   - **Window Match Priority**: `Match title, otherwise find window of same executable`.
4. Click **OK**.

### Why Application Audio Capture is Superior:
- **Zero Desktop Bleed**: Discord calls, Spotify music, Twitch alerts, and Windows notification sounds are excluded from the game track.
- **Multi-Track Recording**: In OBS **Settings > Output > Recording**, assign `iPhone Game Audio` to Track 1 (Stream) and Track 2 (Isolated Audio for Video Editing).

---

## 5. Latency & Performance Tuning for Esports

| Setting | Recommended Value | Why |
|---|---|---|
| **Connection Route** | USB Personal Hotspot | Reduces latency from ~48ms (Wi-Fi) to **~24ms (USB)** |
| **CastSprint Sync Preset** | Low Latency (5ms jitter) | Minimizes video buffering while maintaining stable presentation |
| **OBS Capture Method** | Windows 10 (1903+) | Direct GPU memory sharing; zero CPU readback |
| **GPU Rendering** | Hardware D3D11 | Hardware NV12 video decoding and hardware color conversion |
| **DirectX Swap Effect** | Flip Discard | Eliminates presentation buffer queues |

---

## 6. Managing Stream Interruptions & Reconnections

### iPhone Sleep or Disconnect:
- If the iPhone sleeps, locks, or drops connection, CastSprint displays an offline slate and preserves the window handle.
- OBS Window Capture **does not crash or turn pink**; it retains the last frame or black background until reconnection.
- When the iPhone unlocks and re-engages Screen Mirroring, streaming resumes automatically within 1.5 seconds.

### Changing Orientations (Portrait $\leftrightarrow$ Landscape):
- Dynamic orientation changes send updated resolution descriptors in the AirPlay stream.
- CastSprint's Direct3D 11 swapchain adjusts back-buffer dimensions dynamically.
- In OBS, set the source bounding box to **Scale to inner bounds** to automatically accommodate rotation without manual resizing during a livestream.

---

## 7. Troubleshooting Common Stream Issues

### Issue 1: OBS Shows a Black Screen
- **Fix**: Check if protected commercial media (e.g., Netflix, Disney+, Apple TV+) is playing on the iPhone. FairPlay DRM content is protected by law and cannot be captured. Close DRM video apps and return to gameplay.
- **Fix**: Verify OBS is running with administrator privileges if CastSprint is elevated.

### Issue 2: Audio Delay / Desync
- **Fix**: In CastSprint, press **`[`** or **`]`** to adjust audio sync offset in $\pm 10\text{ ms}$ increments.
- In OBS, open **Advanced Audio Properties** on `iPhone Game Audio` and verify **Sync Offset** is set to `0 ms`.

### Issue 3: CastSprint Desktop Not Appearing in Screen Mirroring
- **Fix**: Verify Windows Firewall allows inbound TCP port `7000` and UDP port `5353` / `7010` on Private/Home networks.
- **Fix**: If using USB Hotspot mode, verify **Settings > Personal Hotspot** is turned ON and Windows Network Connections displays `Apple Mobile Device Ethernet`.
