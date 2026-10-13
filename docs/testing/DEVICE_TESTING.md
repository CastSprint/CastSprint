# Device Testing & Verification Guide

This guide describes how to run, test, and verify the CastSprint Android capture and H.264 hardware encoding engine on physical Android devices and emulators.

---

## 1. Prerequisites

- Android device running Android 10+ (API 29+) or Android emulator (API 29–36).
- USB debugging enabled on the physical device.
- Host machine with `adb` and `ffmpeg` (for `ffprobe` / `ffplay`).
- JDK 17+ and Android SDK configured.

Verify device connectivity:
```bash
adb devices
```

---

## 2. Building & Installing the Android App

From the repository root:
```bash
cd apps/android
./gradlew installDebug
```

Launch the application:
```bash
adb shell am start -n com.castsprint.android/.MainActivity
```

---

## 3. Standalone Verification (Zero PC Software Dependency)

CastSprint includes a built-in diagnostic mode (`Save H.264 (Diag)`) that captures and records the genuine hardware-encoded H.264 bitstream directly to disk. This allows complete end-to-end testing of the capture pipeline without needing the Windows receiver.

### Step-by-Step Procedure

1. In the CastSprint app:
   - Select your desired **Resolution** (`720p` or `1080p`).
   - Select your target **Frame Rate** (`30 FPS` or `60 FPS`).
   - Select your target **Bitrate** (`4M` to `20M`).
   - Under **Output Destination**, tap **`Save H.264 (Diag)`**.
2. Tap **`Start Mirroring`**.
3. In the system MediaProjection consent dialog:
   - Choose **Entire screen** (recommended) or a specific application.
   - Tap **Start now** or **Share screen**.
4. The app status changes to **MIRRORING** (green badge):
   - The notification shade displays the ongoing "CastSprint Screen Mirroring" notification.
   - Live diagnostics display actual encoded FPS, current bitrate, frame count, keyframe count, and dropped frame count.
5. Interact with your device (switch apps, open a game, or scroll).
6. Tap **`Stop Mirroring`** in the app (or via the notification).
7. The status transitions to **IDLE**, and the saved file path is shown in the diagnostics card:
   ```
   /storage/emulated/0/Android/data/com.castsprint.android/files/castsprint_<timestamp>.h264
   ```

---

## 4. Bitstream Inspection & Verification with FFmpeg

Pull the recorded stream to your workstation:
```bash
adb pull /storage/emulated/0/Android/data/com.castsprint.android/files/ build/device_captures/
```

### Inspect NAL Units and Stream Parameters with `ffprobe`

```bash
ffprobe -show_streams build/device_captures/<filename>.h264
```

Expected output verification checklist:
- [x] `codec_name=h264`
- [x] `profile=Constrained Baseline` or `Baseline` / `Main` / `High` (depending on device SoC)
- [x] Dimension matching target bounding box (e.g., `864x1920` for a 1080x2400 phone)
- [x] `extradata_size` > 0 (valid SPS and PPS parameter sets)
- [x] `has_b_frames=0` (low-latency streaming profile)

### Inspect Frame Packets & Keyframe Cadence

```bash
ffprobe -select_streams v -show_frames -show_entries frame=pict_type,key_frame,pkt_pts build/device_captures/<filename>.h264 | head -n 30
```

Verify that the first frame is an `I` frame (`key_frame=1`) followed by `P` frames.

### Play the Bitstream Locally

```bash
ffplay -vf "setpts=N/30/TB" build/device_captures/<filename>.h264
```
*(Replace `30` with `60` if captured at 60 FPS).*

---

## 5. Live USB Streaming Verification (ADB Reverse)

To test the live TCP socket path without the full desktop client:

1. Forward the port from Android to host over USB:
   ```bash
   adb reverse tcp:51820 tcp:51820
   ```
2. Start a TCP listener on the host that dumps received bytes:
   ```bash
   nc -l 51820 > /tmp/stream_dump.bin
   ```
3. In the CastSprint Android app, select **`USB / PC (Protocol)`** and tap **`Start Mirroring`**.
4. The app initiates connection to `127.0.0.1:51820`, executes the CastSprint Protocol v1 handshake, and streams `VIDEO_FRAME` packets over USB.
5. Stop mirroring and verify the received protocol frames.

---

## 6. Logcat Debugging Filters

Monitor the CastSprint capture pipeline in real time:
```bash
adb logcat -s ScreenCaptureService VideoEncoder MainActivity CastSprintSession
```

Key log markers:
- `Selected encoder`: Reports the chosen encoder codec name, dimensions, and hardware acceleration status.
- `Starting encoder`: Reports negotiated resolution, framerate, and target bitrate.
- `Capture session active`: Confirms VirtualDisplay is bound and rendering to the input surface.
- `Emitted VideoConfig`: Confirms CSD (SPS/PPS) has been parsed and transmitted.
- `Stop request received`: Confirms graceful teardown and release of `VirtualDisplay`, `MediaCodec`, and `MediaProjection`.
