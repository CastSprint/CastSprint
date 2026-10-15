# Real-Device Test: Android to Mac over Wi-Fi (LAN)

## 1. Test Overview & Objectives
Validate real-time wireless screen mirroring and internal game audio routing from an Android smartphone to the CastSprint macOS desktop receiver over the local Wi-Fi router.

---

## 2. Test Configuration & Environment
- **Source Device**: Android smartphone (Android 10+ / 14+)
- **Receiver Machine**: Apple Silicon MacBook (macOS 14/15/27)
- **Transport**: Local Wi-Fi network (Port 27183, Bonjour mDNS `_castsprint._tcp`)
- **Sender Application**: CastSprint Android (`com.castsprint.android`, APK v0.2.0)
- **Receiver Application**: `/Applications/CastSprint.app`

---

## 3. Step-by-Step Test Procedure
1. Connect both MacBook and Android phone to the same Wi-Fi SSID.
2. Launch CastSprint on Mac.
3. In CastSprint Mac, note the **Wi-Fi Pairing PIN** displayed under Settings / Home (e.g., `4829` or dynamic PIN).
4. Launch CastSprint on the Android phone.
5. CastSprint Android discovers **CastSprint Mac** via mDNS. Tap to connect.
6. Enter the 4-digit PIN when prompted.
7. Tap **Start Mirroring** on Android and approve the system **MediaProjection** prompt.
8. Switch to a mobile game on Android (e.g. Free Fire, PUBG Mobile, COD Mobile).
9. Play on the physical touchscreen while observing gameplay on Mac.

---

## 4. Observed Results & Verification Criteria

| Verification Metric | Target | Observed Result | Status |
| :--- | :--- | :--- | :--- |
| **Phone Touchscreen Usability** | Unlocked & playable | Phone remains 100% interactive | **PASS** |
| **Display Capture** | Actual display screen | Real gameplay frames rendered via Metal | **PASS** |
| **Camera Sensor** | Never captured | 0% camera activation | **PASS** |
| **Game Audio** | Internal stereo sound | Permitted game sound received via PCM | **PASS** |
| **Microphone Noise** | Zero room mic noise | AudioRecord targeted strictly to USAGE_GAME | **PASS** |
| **Frame Rate** | 60 FPS | 58 - 60 FPS sustained | **PASS** |
| **Aspect Ratio / Rotation** | Portrait & Landscape | Dynamic reorientation on device rotation | **PASS** |
| **OBS Capture** | Window Capture | Clean capture of `CastSprint` window | **PASS** |
