# CastSprint Comprehensive Troubleshooting Guide

This guide covers troubleshooting solutions for video, audio, network connectivity, OBS livestreaming, and performance optimization in CastSprint.

---

## 1. Video & Display Issues

### Issue 1.1: Black screen on PC after connecting
- **Cause 1**: The Android system screen capture permission prompt was dismissed or cancelled.
  - **Fix**: In CastSprint Android, tap **Stop Mirroring**, then tap **Start Mirroring** again. When the system prompt appears, tap **"Start now"** or **"A single app / Entire screen"**.
- **Cause 2**: A DRM-protected application is open on your mobile screen.
  - **Fix**: Android prevents hardware capture of protected media (such as Netflix, Disney+, banking apps, or incognito browsers). Switch to your mobile game or home screen; mirroring will resume immediately.
- **Cause 3**: Hardware encoder surface initialization failed.
  - **Fix**: Select the **Balanced** or **Low Latency** preset (720p or 1080p). Some older devices cannot encode at 2K or 4K.

### Issue 1.2: Image appears stretched or distorted
- **Fix**: Mobile games often run at modern ultrawide aspect ratios (e.g. 20:9 or 19.5:9). CastSprint maintains the native device aspect ratio with letterboxing/pillarboxing. In OBS, right-click the source and select **Transform > Fit to screen** (`Ctrl + F`).

### Issue 1.3: Device rotation causes frozen or black video
- **Fix**: CastSprint automatically transmits a `DISPLAY_CHANGED` packet when you rotate from Portrait to Landscape, reconfiguring the hardware encoder seamlessly. If your device takes more than 1 second to rotate, ensure **Auto-Rotate** is toggled ON in your Android quick settings before launching your game.

---

## 2. Audio Capture & Playback Issues

### Issue 2.1: Mirroring works, but no sound plays on Windows
- **Cause 1**: The device is running Android 9 or older.
  - **Explanation**: `AudioPlaybackCapture` is a native Android API introduced in Android 10 (API 29). Devices on Android 9 or below cannot capture internal game audio without hardware accessories.
- **Cause 2**: The game or app disallows audio capture.
  - **Explanation**: Applications with `android:allowAudioPlaybackCapture="false"` or `USAGE_VOICE_COMMUNICATION` explicitly opt out of audio capture in their app manifests.
- **Cause 3**: Audio capture toggle is OFF.
  - **Fix**: Check CastSprint Android to ensure **Game Audio: ON (48kHz AAC)** is active.
- **Cause 4**: PC receiver is muted.
  - **Fix**: Press **`M`** on the PC receiver to unmute, or adjust volume with the **Up/Down** arrow keys.

### Issue 2.2: Audio and video are out of sync
- **In CastSprint**: Use hotkeys **`[`** (reduce audio delay by 10ms) or **`]`** (increase audio delay by 10ms).
- **In OBS**: Open **Advanced Audio Properties** in the Audio Mixer dock and adjust the **Sync Offset (ms)** for the CastSprint audio source.

---

## 3. Network & Connection Issues

### Issue 3.1: USB mode says "Waiting for receiver"
- **Cause**: Reverse port forwarding is missing.
- **Fix**: Open Command Prompt and run:
  ```cmd
  adb reverse tcp:27183 tcp:27183
  ```
  Ensure `adb devices` shows your device connected in `device` state.

### Issue 3.2: Wi-Fi says "Connection rejected / PIN mismatch"
- **Fix**: Verify the 6-digit **Session PIN** displayed on the PC receiver's title bar and Home tab. Enter the matching PIN in the Android app's Wi-Fi pairing dialog.

### Issue 3.3: Wi-Fi cannot discover desktop receiver
- **Cause 1**: Windows Defender Firewall is blocking inbound connections on TCP port 27183.
  - **Fix**: Allow `castsprint_receiver.exe` or TCP port 27183 in Windows Firewall for Private networks.
- **Cause 2**: AP Client Isolation or Guest Wi-Fi network.
  - **Fix**: Disable "AP Client Isolation" in your router settings, or ensure both phone and PC are connected to your main home Wi-Fi SSID.
- **Cause 3**: Router blocks mDNS multicast packets.
  - **Fix**: Use the **Manual Configuration** fallback in the Android pairing dialog: enter your PC's local IP address and port 27183 manually.

---

## 4. Performance & Thermal Management

### Issue 4.1: Stream bitrate drops automatically after 20 minutes of gaming
- **Cause**: Android hardware thermal throttling.
- **Explanation**: Modern mobile chipsets generate heat when running high-load 3D games (PUBG Mobile, Genshin Impact, Wild Rift) while simultaneously encoding H.264 video.
- **Fix**: CastSprint actively listens to the Android thermal status API (`PowerManager.OnThermalStatusChangedListener`). When the device reports `THERMAL_STATUS_SEVERE`, CastSprint automatically scales bitrate down by 40% to prevent dropped frames and crashes. Once temperatures normalize, bitrate is seamlessly restored. To prevent throttling, remove heavy phone cases, reduce screen brightness, or use a magnetic phone cooler.

### Issue 4.2: High CPU usage on PC
- **Fix**: By default, CastSprint uses Direct3D 11 hardware-accelerated presentation and Media Foundation hardware decoding. If your graphics driver is outdated, CastSprint may fall back to Microsoft WARP (software emulation). Update your NVIDIA, AMD, or Intel GPU drivers to the latest version.

---

## 5. Local MP4 Recording Issues

### Issue 5.1: Recorded MP4 file is unplayable or 0 bytes
- **Fix**: Always click **Stop Recording** (or press **`R`**) before closing the receiver window. CastSprint uses the Media Foundation Sink Writer in zero-transcode passthrough mode; cleanly stopping the recording writes the container `moov` atom header, finalizing the MP4 file for playback in VLC, Windows Media Player, and video editing software.

### Issue 5.2: Disk full error during long recording
- **Fix**: CastSprint records at up to 12-20 Mbps (approximately 5-9 GB per hour). Ensure your target drive has sufficient free storage space. You can change the recording destination in the Recording tab.
