# CastSprint OBS Studio Livestreaming Guide

CastSprint is built from the ground up for mobile game livestreaming to YouTube, Twitch, Facebook Gaming, and Kick with zero watermarks, zero subscriptions, and ultra-low latency.

---

## 1. Prerequisites
- **CastSprint Windows Receiver** installed on your PC.
- **CastSprint Android App** installed on your Android device (Android 10+).
- **OBS Studio 29.0+** (64-bit).
- Connection cable: High-quality USB-C to USB-A/C cable (for USB mode) **OR** a 5GHz Wi-Fi router (for wireless LAN mode).

---

## 2. Connecting Your Android Device

### Mode A: Native USB (Recommended for Competitive Gaming)
1. On your phone, go to **Settings > About Phone** and tap **Build Number** 7 times to enable Developer Options.
2. Go to **Settings > System > Developer Options** and toggle **USB Debugging** ON.
3. Connect your phone to your PC via USB and allow the USB debugging prompt.
4. On your PC, open a command prompt or terminal and execute:
   ```cmd
   adb reverse tcp:27183 tcp:27183
   ```
5. Open CastSprint on Android, select **USB (ADB reverse)**, and tap **Start Mirroring**.

### Mode B: Secure Wi-Fi (Cable-Free)
1. Ensure both your phone and PC are connected to the same Wi-Fi network (5GHz recommended).
2. Launch CastSprint on Windows. The title bar and Home tab display your 6-digit **Session PIN** and SHA-256 certificate fingerprint.
3. Open CastSprint on Android, select **Secure Wi-Fi (LAN)**, tap **Configure / Discover PC**, select your desktop from the list (or enter the IP and PIN), and tap **Start Mirroring**.

---

## 3. Adding CastSprint as a Video Source in OBS

For highest performance and zero frame drops, use **Window Capture**:

1. In OBS Studio, locate the **Sources** dock and click the **`+`** icon.
2. Select **Window Capture** and name it `CastSprint Mobile Game`.
3. In the properties window:
   - **Window**: Select `[castsprint_receiver.exe]: CastSprint - Gaming View`.
   - **Capture Method**: Select **`Windows 10 (1903 and up)`** (this utilizes the Windows Graphics Capture API for zero-copy Direct3D 11 capture).
   - **Window Match Priority**: Select `Match title, otherwise find window of same executable`.
   - **Capture Cursor**: Uncheck if you do not want your desktop cursor visible over the mobile game.
4. Click **OK**.

> [!TIP]
> **Borderless Fullscreen Mode**: Press **`F11`** in CastSprint Receiver to toggle borderless fullscreen. OBS Window Capture continues capturing the dedicated viewport seamlessly.

---

## 4. Capturing Game Audio in OBS

CastSprint streams 48kHz stereo mobile game audio directly to Windows via WASAPI shared-mode.

### Recommended Method: Application Audio Capture (OBS 28+)
This isolates the game audio from Discord, Spotify, or desktop alerts:
1. Under **Sources**, click **`+`** and select **Application Audio Capture (BETA)**.
2. Name it `CastSprint Game Sound`.
3. In the **Window** dropdown, select `[castsprint_receiver.exe]: CastSprint`.
4. Click **OK**.

### Alternative Method: Desktop Audio
If using standard Desktop Audio in OBS, CastSprint game audio automatically routes to your default playback device.

---

## 5. Streaming Resolution and Aspect Ratio Scaling

Mobile screens often use wide gaming aspect ratios such as **20:9**, **19.5:9**, or **16:9** (e.g. 2400x1080).
1. In OBS, right-click the `CastSprint Mobile Game` source.
2. Go to **Transform > Fit to screen** (`Ctrl + F`).
3. If streaming at 1080p (1920x1080 16:9), the mobile game will display centered with clean pillarboxes. You can place your webcam, stream chat, and overlays in the side borders.

---

## 6. Correcting Audio/Video Synchronization

CastSprint incorporates hardware-synchronized timestamps (`AvSynchronizer`), but different Bluetooth headphones or virtual audio cables may introduce audio latency.

1. **In CastSprint**:
   - Press **`[`** to reduce audio delay by 10ms.
   - Press **`]`** to increase audio delay by 10ms.
   - Current offset is shown in the Stream Settings tab.
2. **In OBS (Fine Tuning)**:
   - Click the gear icon in the **Audio Mixer** and choose **Advanced Audio Properties**.
   - Locate `CastSprint Game Sound`.
   - Adjust **Sync Offset (ms)** as needed (typically 0ms to 40ms).

---

## 7. Avoiding Duplicate Audio & Echo

- When streaming mobile games, mute your phone's physical media volume or connect earphones to your PC. CastSprint's `AudioPlaybackCapture` captures internal game audio digitally before device speakers.
- Ensure you do not add both **Application Audio Capture** and **Desktop Audio** for the same output in OBS, which causes double playback.

---

## 8. Starting Your Stream

1. In OBS, navigate to **Settings > Stream**.
2. Select your platform: **Twitch**, **YouTube - RTMPS**, or **Facebook Live**.
3. In **Settings > Output**:
   - Video Encoder: **NVIDIA NVENC H.264** or **AMD HW H.264**.
   - Rate Control: **CBR**.
   - Bitrate: **6000 Kbps** (for 1080p60 on Twitch/YouTube).
   - Keyframe Interval: **2 seconds**.
4. Click **Start Streaming**. You are now live with native 60 FPS mobile gaming!

---

## 9. Minimization and Background Behavior

- Do **not** minimize the CastSprint receiver window to the taskbar while streaming with OBS Window Capture. Windows stops rendering D3D11 swap chains for minimized windows to conserve power.
- Instead, keep CastSprint running in the background behind OBS or move it to a secondary monitor.
