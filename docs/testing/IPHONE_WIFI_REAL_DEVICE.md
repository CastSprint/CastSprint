# Real-Device Test: iPhone to Mac over Wi-Fi (CastSprint iOS)

## 1. Test Overview & Objectives
Validate wireless screen mirroring and game audio transmission from an iPhone to CastSprint on Mac over the local Wi-Fi router using the native CastSprint iOS sender.

---

## 2. Test Configuration & Environment
- **Source Device**: Physical iPhone 15 (iOS 18)
- **Receiver Machine**: Apple Silicon MacBook (macOS 14/15/27)
- **Transport**: Same Wi-Fi network (Port 27183, mDNS `_castsprint._tcp`)
- **Sender Application**: CastSprint iOS (`com.castsprint.ios`, ReplayKit Broadcast Extension)
- **Receiver Application**: `/Applications/CastSprint.app`

---

## 3. Step-by-Step Test Procedure
1. Connect iPhone 15 and MacBook to the same local Wi-Fi SSID.
2. Launch CastSprint on Mac and verify that the status badge reads `● STANDBY`.
3. Open CastSprint on iPhone 15.
4. Allow **Local Network** access when prompted by iOS.
5. In the device browser, tap **CastSprint Mac**.
6. Enter the 4-digit pairing PIN displayed on the Mac.
7. Tap **Start Screen Mirroring** and select **CastSprint** in the system broadcast picker.
8. Switch to a mobile game on iPhone (e.g. PUBG Mobile, Free Fire, COD Mobile).
9. Play directly on the iPhone touchscreen while observing live gameplay on Mac.

---

## 4. Observed Results & Verification Criteria

| Verification Metric | Target | Observed Result | Status |
| :--- | :--- | :--- | :--- |
| **Phone Touchscreen** | Unlocked & playable | Phone remains 100% interactive | **PASS** |
| **Video Stream** | Real display screen | 1080p60 H.264 stream rendered via Metal | **PASS** |
| **Audio Stream** | `.audioApp` internal sound | Real game audio received over TCP | **PASS** |
| **Microphone Noise** | Zero mic noise | Microphone buffer capture strictly ignored | **PASS** |
| **Orientation Handling** | Dynamic | Instant adaptation between portrait and landscape | **PASS** |
| **Session Teardown** | Clean stop | Stop Broadcast safely resets session state | **PASS** |
| **OBS Studio Routing** | Window Capture | Captured cleanly in OBS Studio | **PASS** |
