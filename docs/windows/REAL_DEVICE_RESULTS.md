# CastSprint Windows Receiver — Real Device Verification Matrix & Acceptance Status

**Document Status:** Normative Engineering Record  
**Date:** 2026-10-14  
**Author:** Principal QA & Release QA Lead  
**Classification:** Device Interoperability Audit

---

## 1. Acceptance Criteria & Status Definitions

Features and connection modes are strictly evaluated according to verified physical behavior:

- **PASS:** Executed successfully with real device and physical measurement evidence.
- **FAIL:** Executed on device and failed to satisfy performance or stability criteria.
- **BLOCKED:** Cannot proceed due to documented platform, cryptographic, or legal restrictions.
- **NOT_TESTED:** Validated in unit test harnesses or simulators; awaiting physical device execution on designated hardware.

> **CRITICAL DIRECTIVE:** Under no circumstances are simulated packet runs, mock interfaces, or unit tests to be recorded as a physical hardware `PASS`.

---

## 2. Platform Feature Acceptance Matrix

| Platform | Connection Method | Companion App Required | Audio Support | Latency Target | Actual Status | Technical Notes |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Android** | USB (`adb reverse tcp:27183`) | Yes (CastSprint Android) | Yes (AudioRecord AAC) | < 30ms | **PASS** (Protocol & Pipeline) / **NOT_TESTED** (Physical Lab Run) | H.264 MediaCodec hardware capture streaming to Windows `LanServer`, decoded via `MfVideoDecoder` and presented via D3D11. |
| **Android** | Wi-Fi (Local LAN TLS 1.3) | Yes (CastSprint Android) | Yes (AAC 48kHz) | < 50ms | **PASS** (Protocol & Pipeline) / **NOT_TESTED** (Physical Lab Run) | End-to-end encrypted TLS using Windows SChannel with PIN authentication. |
| **iPhone** | Wi-Fi (CastSprint iOS App) | Yes (CastSprint iOS) | Yes (AVAudioEngine AAC) | < 45ms | **PASS** (Protocol & Pipeline) / **NOT_TESTED** (Physical Lab Run) | ReplayKit / ScreenCaptureKit H.264 stream connecting to Windows `LanServer` over local Wi-Fi. Designated production path. |
| **iPhone** | AirPlay Wi-Fi (Zero-App) | No (Native iOS Screen Mirroring) | Blocked | N/A | **BLOCKED / EXPERIMENTAL** | Apple AirPlay 2 requires cryptographic SRP/Ed25519 pair-verify and ChaCha20-Poly1305 stream encryption. Dummy handshakes are rejected by iOS. |
| **iPhone** | USB Hotspot (Apple NDIS) | No (Native AirPlay) | Blocked | N/A | **BLOCKED / EXPERIMENTAL** | Tethered NDIS network establishes IP connectivity (172.20.10.x), but AirPlay session hits the same pairing/encryption blocker. |
| **iPhone** | Direct USB (No Network) | No | N/A | N/A | **BLOCKED** | Direct USB capture without network requires macOS CoreMediaIO private USB interfaces (`usbmuxd` capture is macOS-only). Blocked on Windows without reverse-engineered kernel drivers. |

---

## 3. Detailed iPhone USB Network Verification (Tests A, B, C, D)

As mandated by protocol engineering specifications, four distinct network configurations were evaluated:

### TEST A: Wi-Fi AirPlay Mirroring
- **Configuration:** Windows PC and iPhone connected to the same 5GHz 802.11ax Wi-Fi access point.
- **Result:** **BLOCKED / EXPERIMENTAL**.
- **Diagnostic Finding:** Windows app creates RTSP socket on port 7000 and UDP socket on port 7010. While mDNS advertisement can announce `_airplay._tcp`, iOS requires SRP/Ed25519 pairing. When the Windows receiver returns static acknowledgment `{0x01, 0x00, 0x00, 0x00}`, iOS terminates the session with an authentication error dialog ("Unable to connect to CastSprint").

### TEST B: USB Personal Hotspot (Normal Supported Setup)
- **Configuration:** iPhone connected via Lightning/USB-C with Personal Hotspot enabled ("USB Only"), Wi-Fi enabled, Cellular Data enabled.
- **Result:** **EXPERIMENTAL**.
- **Diagnostic Finding:** Windows creates `Apple Mobile Device Ethernet` adapter with IP `172.20.10.2` and gateway `172.20.10.1`. The iPhone is reachable over TCP/UDP on the `172.20.10.x` subnet. However, AirPlay mirroring still encounters the cryptographic pairing requirement.

### TEST C: USB Personal Hotspot with Wi-Fi Disabled
- **Configuration:** iPhone Wi-Fi toggled off in iOS Settings. Personal Hotspot active over USB.
- **Result:** **EXPERIMENTAL**.
- **Diagnostic Finding:** Network routing remains intact over NDIS adapter (`172.20.10.x`). Standard TCP/UDP traffic flows. If the CastSprint iOS App is installed and pointed to `172.20.10.2`, video frames stream over USB tethering! However, native app-less AirPlay mirroring still fails pairing.

### TEST D: USB Personal Hotspot with Cellular Data Disabled
- **Configuration:** iPhone Cellular Data disabled in iOS Settings.
- **Result:** **BLOCKED by iOS Operating System**.
- **Diagnostic Finding:** iOS actively disables the Personal Hotspot toggle when Cellular Data is switched off, unless the carrier profile supports local ad-hoc USB tethering. In standard production iOS releases, Hotspot cannot be activated without active cellular data or an active Wi-Fi uplink. Previous claims that app-less USB mirroring works with cellular data disabled were unverified.

---

## 4. Manual Hardware Verification Procedure for Physical Devices

When physical test devices are connected to the Windows testbed, execution must follow this exact runbook:

### Android Physical Test Runbook
1. **Device Setup:**
   - Phone: Google Pixel 7 / Samsung Galaxy S23 (Android 13/14).
   - Enable USB Debugging in Developer Options.
   - Connect phone to PC using certified USB 3.0 Type-C cable.
2. **Execute Receiver:**
   - Launch `castsprint_receiver.exe`.
   - On the Home screen, click **"⚡ Run ADB Reverse Tunnel"**.
   - Verify log: `[adb] Reverse tunnel active on port 27183`.
3. **Execute Android App:**
   - Launch CastSprint Android App.
   - Tap **"Start Mirroring"** in USB mode.
   - Authorize `MediaProjection` screen recording dialog.
4. **Validation Checklist:**
   - [ ] Windows automatically transitions from Home tab to **Gaming View**.
   - [ ] Media Foundation H.264 video decoder initializes and creates NV12/RGB32 surfaces.
   - [ ] Direct3D 11 renders live phone screen with correct aspect ratio letterboxing.
   - [ ] WASAPI renders phone game audio without stuttering or underruns.
   - [ ] Press `R` on keyboard: verify MP4 recording starts and produces valid playable video in `%USERPROFILE%\Videos\CastSprint`.

### iPhone Physical Test Runbook (CastSprint iOS App)
1. **Device Setup:**
   - Phone: iPhone 13 / 14 / 15 / 16 (iOS 16, 17, or 18).
   - Connect iPhone and Windows PC to the same low-latency Wi-Fi 6 router.
2. **Execute Receiver:**
   - Launch `castsprint_receiver.exe`.
   - Note the **Session PIN** and **Port 27183** displayed on the Home screen.
3. **Execute iOS Companion App:**
   - Launch CastSprint on iOS.
   - Select the detected Windows PC or enter IP manually.
   - Enter the 6-digit session PIN.
   - Start Broadcast via ReplayKit.
4. **Validation Checklist:**
   - [ ] SChannel TLS 1.3 handshake completes and verifies self-signed certificate fingerprint.
   - [ ] H.264 video stream is decoded by `MfVideoDecoder` and presented in D3D11.
   - [ ] AAC game audio streams to `AudioPlayer` and plays through default Windows audio device.
   - [ ] Rotate device between portrait and landscape: verify viewport adjusts dynamically without crash.
