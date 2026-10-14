# CastSprint iOS — Physical Device Testing Guide

This guide details the step-by-step procedures for testing **CastSprint for iPhone and iPad** against Windows and macOS desktop receivers on physical hardware.

---

## 1. Test Environment Prerequisites

- **Sender Devices**:
  - iPhone (iOS 15.0 or later; recommended iPhone 11 or later for optimal 60 FPS hardware encoding).
  - iPad / iPad Pro (iPadOS 15.0 or later).
- **Receiver Devices**:
  - Windows PC running CastSprint Windows Receiver (`lan_server` / D3D11 renderer).
  - Mac running CastSprint macOS Receiver (`CastSprintMac.app`).
- **Network**:
  - Both devices connected to the same 5 GHz Wi-Fi network (or Wi-Fi 6).
  - AP Isolation / Client Isolation disabled on the Wi-Fi router.
  - Port `27183` accessible locally.

---

## 2. Test Execution Matrix

### Test 1: First-Time Permissions & Onboarding
1. Install CastSprint build on iPhone via Xcode or TestFlight.
2. Launch the application.
3. Verify that the app prompts for **Local Network** permission upon initial Bonjour discovery or connection attempt.
4. Verify that camera permission is only prompted when the user taps "Scan Desktop QR Code".
5. Verify that microphone permission is never requested unless the user enables "Microphone Commentary" in settings.

### Test 2: Receiver Discovery (Bonjour & Manual IP)
1. Launch CastSprint Desktop on a Windows PC or Mac on the same network.
2. Verify that the computer appears in the "DISCOVERED COMPUTERS" list within 2 seconds with its correct platform badge (`Mac` or `PC`).
3. Tap the discovered computer and verify that the target IP and PIN are populated automatically.
4. Test manual IP fallback: enter `192.168.x.x` manually and verify connection.

### Test 3: QR Code Pairing
1. On CastSprint Desktop, display the pairing QR code.
2. On iPhone, navigate to the "Pairing" tab and tap "Scan Desktop QR Code".
3. Point camera at desktop monitor.
4. Verify immediate haptic feedback and that the receiver IP, PIN, and device name are populated.

### Test 4: Screen Capture Initiation & System Picker
1. In CastSprint iOS, tap "Launch Broadcast Picker".
2. Verify that the Apple system broadcast picker modal appears.
3. Verify that "CastSprint" is pre-selected as the broadcast extension.
4. Tap "Start Broadcast" and observe the 3-second system countdown.
5. Verify that the system status bar indicates active recording (red pill or dynamic island broadcast icon).
6. Verify that the session timer and live throughput indicator begin updating in the app.

### Test 5: Real Gameplay Streaming & 60 FPS Video Performance
1. Switch to a demanding mobile game (e.g. *Genshin Impact*, *PUBG Mobile*, *Call of Duty: Warzone Mobile*, or *Asphalt 9*).
2. Play continuously for 15+ minutes.
3. Verify on the desktop receiver:
   - Video is smooth at 60 FPS with no stutter.
   - Latency feels responsive (< 20 ms on 5 GHz Wi-Fi).
   - Video quality is sharp with no blocky compression artifacts at 12 Mbps (Balanced) or 20 Mbps (High Quality).
4. Rotate device between Portrait and Landscape:
   - Verify that the encoder dynamically reconfigures without disconnecting.
   - Verify that desktop receiver adapts its viewport.

### Test 6: Synchronized Game Audio Verification
1. Ensure game sound effects and background music are active in the game.
2. Verify on desktop receiver:
   - Internal game sound is received clearly in stereo.
   - Audio and video remain lip-synced and synchronized with in-game actions (e.g., weapon firing, button taps).
3. Toggle "Microphone Commentary":
   - Speak into the iPhone microphone.
   - Verify voice commentary mixes cleanly with game audio on desktop.

### Test 7: Memory & Watchdog Compliance (50 MB Ceiling)
1. In Xcode Instruments, attach the **Allocations** and **Memory Usage** templates to `LegacyBroadcastExtension`.
2. Stream 1080p 60 FPS video for 30 minutes under high visual motion.
3. Verify that resident memory (`Dirty Memory`) remains strictly below **25 MB**, well below Apple's 50 MB termination limit.
4. Verify zero memory leaks across frame rotations.

### Test 8: Interruption & Recovery Handling
1. **Incoming Call**: Receive a phone call during active streaming; verify that capture pauses cleanly and resumes after the call.
2. **Device Lock**: Lock the iPhone screen; verify that the desktop receiver displays a graceful pause state without crashing.
3. **Wi-Fi Drop**: Turn off Wi-Fi; verify that the app and desktop receiver report a clean disconnect without freezing.
4. **Desktop Receiver Close**: Close CastSprint on PC/Mac; verify that the iOS broadcast extension gracefully halts without crashing.

---

## 3. Verification Boundary & Physical Device Disclaimer

> [!NOTE]
> Unit tests and compiler typechecks have been 100% verified against Xcode 26.5 and `iPhoneSimulator26.5.sdk` on macOS Apple Silicon. Full end-to-end Wi-Fi streaming requires running the app on a physical iPhone and CastSprint Desktop on a physical PC or Mac connected to the same Wi-Fi network.
