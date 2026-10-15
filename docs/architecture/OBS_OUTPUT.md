# CastSprint — OBS Studio Livestreaming Integration Guide

## 1. Overview
CastSprint is engineered from the ground up as an OBS-first capture companion. Livestreamers on YouTube, Twitch, Facebook Gaming, and Kick rely on CastSprint to deliver smooth 60 FPS gameplay with zero UI clutter.

---

## 2. OBS Video Setup: Dedicated Window Capture

### 2.1 macOS Setup
1. Launch **CastSprint** and connect your mobile device (iPhone 15 or Android).
2. Start Mirroring and navigate to **Mirror View** in CastSprint.
3. Open **OBS Studio**.
4. In your Scene, click the **+** (Add Source) button.
5. Select **macOS Screen Capture**.
6. Set the Method to **Window Capture**.
7. In the Window dropdown, select **[CastSprint] CastSprint**.
8. Optional: In CastSprint's Mirror View, click **CLEAN OBS FEED** to hide the top recording and FPS overlays for an immaculate stream feed.

### 2.2 Windows Setup
1. In OBS Studio, click **+** ➔ **Window Capture**.
2. Select **[CastSprint.exe]: CastSprint - Gameplay**.
3. Set Capture Method to **Windows 10 (1903 and up)** for zero-lag DirectX 11 capture.

### 2.3 Linux Setup
- **Wayland**: Add **Screen Capture (PipeWire)** ➔ **Window** ➔ Select CastSprint.
- **X11**: Add **Window Capture (Xcomposite)** ➔ Select CastSprint.

---

## 3. OBS Audio Setup: Internal Game Sound

### 3.1 iPhone over USB (macOS)
1. In CastSprint, click **ENABLE USB DIGITAL AUDIO (AUDIO MIDI SETUP)**.
2. In the Audio Devices window, click **Enable** next to your connected iPhone.
3. In OBS Studio:
   - Click **+** ➔ **Audio Input Capture**.
   - Device: Select **iPhone**.
4. Result: Pure digital internal game sound directly into OBS with 0% microphone noise.

### 3.2 Android / Wi-Fi Streaming
- In OBS Studio, add **macOS Application Audio Capture** (macOS 13+) or **Application Audio Output Capture** (Windows 10/11) targeting `CastSprint`.
