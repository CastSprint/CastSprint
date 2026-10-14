# CastSprint — OBS Studio Master Streaming & Recording Guide

This guide details the exact configurations for capturing clean, watermark-free, ultra-low-latency mobile gameplay from **CastSprint for Windows and macOS** in **OBS Studio** (v29.0+ / v30.0+ / v31.0+).

---

## 1. Golden Rules for OBS Mobile Game Streaming

1. **Zero Watermarks:** CastSprint outputs clean, full-resolution gameplay video with no logos, timers, or forced overlays.
2. **Clean Game Feed Mode:** In CastSprint, switch to **"Gaming View"** (`[2]` or tap the view toggle) or press `F11` for borderless fullscreen. This renders only the mobile device's pure display output.
3. **Never Use Display Capture:** Always use **Window Capture (macOS ScreenCaptureKit or Windows WGC)**. Window Capture captures frames directly from the application's Metal/Direct3D presentation surface with zero desktop compositing overhead.
4. **Sub-Frame Audio Synchronization:** Route game audio directly through OBS's native Application Audio Capture to eliminate desktop mic echo and ensure perfect lip-sync.

---

## 2. Dedicated Setup Guides by Connection Path

### Path 1: iPhone USB -> macOS (Tournament Grade: <15ms Latency)

```
[iPhone] ---> USB-C / Lightning Cable ---> [MacBook Pro / Mac mini]
                                                  |
                                                  +---> CastSprint macOS (Gaming View)
                                                  |           |
                                                  v           v
                                           [OBS Studio: Window Capture (ScreenCaptureKit)]
```

#### Step-by-Step Configuration:
1. Connect your iPhone to your Mac via USB cable and unlock the device. Tap **Trust** if prompted.
2. Launch **CastSprint Mac**. Select your iPhone in the device list.
3. Switch CastSprint to the **"Mirror"** tab (or press `Cmd+2`).
4. In **OBS Studio (macOS)**:
   * In the **Sources** dock, click **`+`** and choose **macOS Screen Capture**.
   * Under **Method**, select **Window Capture**.
   * Under **Window**, select `[CastSprint]: CastSprint — Gaming View`.
   * Uncheck **Show Cursor** if you want a clean tournament feed without desktop mouse interference.
5. **Game Audio Routing in OBS**:
   * Click **`+`** in Sources and choose **Application Audio Capture (BETA)**.
   * Under **Window**, select `[CastSprint]: CastSprint`.
   * In the OBS Audio Mixer, verify the CastSprint meter bounces with in-game music and sound effects.

---

### Path 2: iPhone Wi-Fi -> macOS (ReplayKit Local LAN: <45ms Latency)

1. Connect your iPhone and Mac to the same 5 GHz Wi-Fi network.
2. Open **CastSprint Mac**. Note the 4-digit pairing PIN displayed in the header.
3. Open **CastSprint iOS** on your iPhone.
4. Tap your Mac in the **Discovered Computers** list (or enter IP / scan QR code).
5. In CastSprint iOS, tap **"Launch Broadcast Picker"** -> select **CastSprint** -> tap **"Start Broadcast"**.
6. Switch to your mobile game on iPhone.
7. In **OBS Studio (macOS)**:
   * Add a **macOS Screen Capture** source -> **Window Capture** -> `[CastSprint]: CastSprint — Gaming View`.
   * Add **Application Audio Capture (BETA)** -> `[CastSprint]: CastSprint`.

---

### Path 3: iPhone Wi-Fi -> Windows 10/11 (<46ms Latency)

```
[iPhone] ---> 5GHz Wi-Fi LAN ---> [Windows PC]
                                        |
                                        +---> CastSprint Windows (Direct3D 11 Surface)
                                        |           |
                                        v           v
                                 [OBS Studio: Window Capture (Windows Graphics Capture)]
```

#### Step-by-Step Configuration:
1. Ensure your PC and iPhone are on the same Wi-Fi subnet (AP isolation disabled).
2. Launch **CastSprint Windows**. The status bar will show `● LISTENING` on port `27183` and display the pairing PIN.
3. Open **CastSprint iOS** on iPhone. Select your PC from the discovered list or enter the PC's local IP.
4. Tap **"Launch Broadcast Picker"** -> **Start Broadcast**.
5. Switch CastSprint Windows to **Gaming View** (press `2` on keyboard or click `[2] Gaming View`).
6. In **OBS Studio (Windows)**:
   * In Sources, click **`+`** -> select **Window Capture**.
   * Under **Window**, select `[castsprint_receiver.exe]: CastSprint — Gaming View`.
   * Under **Capture Method**, choose **Windows 10 (1903 and up) / Windows Graphics Capture (WGC)**. (WGC captures Direct3D 11 swapchains with zero stutter and perfect 60 FPS pacing).
   * Set **Window Match Priority** to `Match title, otherwise find window of same executable`.
7. **Game Audio Capture in Windows OBS**:
   * In Sources, click **`+`** -> select **Application Audio Output Capture (BETA)**.
   * Select `[castsprint_receiver.exe]: CastSprint`.
   * Your viewers will hear crystal-clear stereo game audio without capturing Discord or desktop notifications!

---

### Path 4: Android USB -> macOS (ADB Reverse: <28ms Latency)

1. Connect Android phone to Mac via USB cable.
2. Enable **Developer Options** and **USB Debugging** on the Android phone. Tap **Allow USB Debugging** on the phone screen.
3. Launch **CastSprint Mac**.
4. In the devices dropdown, select your phone under **"Android Devices (USB)"**.
5. CastSprint automatically configures `adb reverse tcp:27183 tcp:27183` and launches the Android app.
6. On Android, tap **"Start Mirroring"** and approve the standard MediaProjection prompt.
7. In **OBS Studio (macOS)**:
   * Add **macOS Screen Capture** -> **Window Capture** -> `[CastSprint]: CastSprint — Gaming View`.
   * Add **Application Audio Capture (BETA)** -> `[CastSprint]: CastSprint`.

---

### Path 5: Android Wi-Fi -> macOS (Local LAN TLS: <52ms Latency)

1. Ensure Android phone and Mac are connected to the same Wi-Fi network.
2. Launch **CastSprint Mac**. Note the session PIN.
3. Open **CastSprint Android**. Select **Wi-Fi Mode**.
4. Tap your Mac in the discovered devices list, enter the PIN, and tap **"Connect & Stream"**.
5. In **OBS Studio (macOS)**:
   * Add **macOS Screen Capture** -> **Window Capture** -> `[CastSprint]: CastSprint — Gaming View`.
   * Add **Application Audio Capture (BETA)** -> `[CastSprint]: CastSprint`.

---

## 3. Recommended OBS Output & Canvas Settings for Mobile Gaming

For optimal streaming quality to Twitch, YouTube Gaming, Kick, or TikTok Live:

| Setting | Recommended Value | Notes |
|:---|:---|:---|
| **Base (Canvas) Resolution** | `1920 × 1080` | Standard 16:9 canvas. Mobile 19.5:9 or 20:9 games fit neatly with side overlays or full vertical fit. |
| **Output (Scaled) Resolution** | `1920 × 1080` | Avoid downscaling on CPU if GPU encoder is used. |
| **Downscale Filter** | Lanczos (36 samples) | Sharpest rendering for high-DPI text and UI elements. |
| **Common FPS Values** | `60` | Matches CastSprint’s 60 FPS output. |
| **Video Encoder** | Apple VideoToolbox H.264 (Mac) / NVIDIA NVENC H.264 (PC) | Hardware-accelerated; zero CPU frame drops. |
| **Rate Control** | CBR (Constant Bitrate) | Twitch: 6,000–8,000 kbps; YouTube: 10,000–14,000 kbps. |
| **Keyframe Interval** | 2 seconds | Required by Twitch and YouTube ingestion. |
| **Audio Bitrate** | 160 kbps (Stereo) | Clean high-fidelity game sound. |

---

## 4. Troubleshooting OBS Capture

* **Black Screen in OBS Window Capture:**
  * On macOS: Ensure OBS Studio has **Screen Recording** permission in `macOS System Settings -> Privacy & Security -> Screen Recording`.
  * On Windows: Change Capture Method from `Automatic` to `Windows Graphics Capture (WGC)`.
* **Stuttering / Dropped Frames in Stream:**
  * Verify that CastSprint's in-app FPS meter reads 60.0 FPS.
  * In OBS, run as Administrator (on Windows) or check OBS Stats (`View -> Stats`) to determine whether drops are due to "Rendering Lag" (GPU overload) or "Encoding Lag" (encoder overload).
* **Audio Drift in Long Sessions:**
  * In OBS Advanced Audio Properties (`Edit -> Advanced Audio Properties`), ensure CastSprint Audio is set to `Sync Offset: 0 ms` and `Audio Monitoring: Monitor Off` (to prevent hearing double).
