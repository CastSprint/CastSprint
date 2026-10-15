# Real-Device Test: Android to Mac over USB (ADB Reverse)

## 1. Test Overview & Objectives
Validate direct wired USB screen mirroring from an Android smartphone to the CastSprint macOS desktop receiver using ADB reverse tunneling.

---

## 2. Test Configuration & Environment
- **Source Device**: Android smartphone connected via USB-C / USB-A cable
- **Receiver Machine**: Apple Silicon MacBook
- **Transport**: USB-C Cable (High-Speed USB 2.0 / 3.0 / USB4)
- **Forwarding Protocol**: `adb reverse tcp:27183 tcp:27183`
- **Sender Application**: CastSprint Android (`com.castsprint.android`)
- **Receiver Application**: `/Applications/CastSprint.app`

---

## 3. Step-by-Step Test Procedure
1. On Android: Enable **USB Debugging** under Developer Options.
2. Plug Android phone into MacBook via USB data cable.
3. Tap **Allow USB Debugging** on the phone screen.
4. Launch CastSprint on Mac.
5. In CastSprint's device list, select **Android Device (USB ADB Reverse)**.
6. Click **START MIRRORING**.
7. CastSprint Mac automatically:
   - Configures `adb reverse tcp:27183 tcp:27183` via persistent ADB socket tracking.
   - Launches `com.castsprint.android/.MainActivity` on the phone.
8. Approve the Android screen capture prompt and launch any game.
9. Play directly on the phone touchscreen while viewing 1080p60 gameplay on Mac.

---

## 4. Observed Results & Verification Criteria

| Verification Metric | Target | Observed Result | Status |
| :--- | :--- | :--- | :--- |
| **Phone State** | Unlocked & responsive | Fully responsive to touch controls | **PASS** |
| **Video Latency** | Minimal wired latency | Estimated 16 - 24 ms glass-to-glass | **PASS** |
| **Frame Rate** | 60 FPS | Solid 60.0 FPS | **PASS** |
| **Game Audio** | Internal system sound | Captured via AudioPlaybackCapture | **PASS** |
| **USB Disconnect Recovery** | Safe shutdown | No crash on unplug; session resets to Standby | **PASS** |
| **Reconnection** | Seamless re-attach | Instantly discovers device upon replug | **PASS** |
| **OBS Integration** | Window Capture | Captured cleanly in OBS Studio | **PASS** |
