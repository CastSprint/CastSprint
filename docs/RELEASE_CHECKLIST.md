# CastSprint Release & Quality Assurance Checklist

This checklist must be executed and verified before every public beta and production release of CastSprint.

---

## 1. Automated Test Verification

| Test Suite | Location | Target | Requirement | Status |
|---|---|---|---|---|
| **Protocol Codec Tests** | `tests/protocol` | C++20 Host | 153 checks, 0 failures | PASS |
| **AV Synchronizer Tests** | `tests/sync` | C++20 Host | 10 checks, 0 failures | PASS |
| **Session Manager Tests** | `tests/session` | C++20 Host | 19 checks, 0 failures | PASS |
| **Android Unit Tests** | `apps/android` | JVM / Robolectric | 36 unit tests, 0 failures | PASS |
| **Android Lint** | `apps/android` | Android SDK | Zero errors under `-Werror` | PASS |
| **Windows Smoke Test** | `apps/windows` | Win32 / D3D11 | `--smoke-test` renders 3 frames and exits with code 0 | Pending Windows MSVC |

---

## 2. Manual Hardware Verification Matrix

| Test Scenario | Procedure | Expected Result | Verified On |
|---|---|---|---|
| **Permission Denied** | Dismiss Android MediaProjection prompt | Session transitions cleanly to `IDLE` with "Permission cancelled by user". No crash. | Android Emulator (API 36.1) |
| **Screen Rotation** | Rotate phone from Portrait to Landscape | `DISPLAY_CHANGED` packet emitted, encoder reconfigured seamlessly, aspect ratio preserved. | Verified |
| **USB Unplug** | Disconnect USB cable during active mirror | Socket closes cleanly, Android foreground service stops, PC transitions to `LISTENING`. | Test Procedure Defined |
| **Wi-Fi Drop** | Toggle Airplane Mode during active Wi-Fi stream | Android network sink triggers retry with bounded exponential backoff; PC displays Reconnecting. | Test Procedure Defined |
| **Rapid Connect/Disconnect** | Tap Start and Stop Mirroring 5 times rapidly | Service starts/stops cleanly, virtual display released, no orphaned threads or memory leak. | Android Emulator (API 36.1) |
| **Audio Capture (Allowed)** | Play mobile game with audio enabled | 48kHz stereo AAC audio streams to PC and plays cleanly through WASAPI. | Test Procedure Defined |
| **Audio Capture (Blocked)** | Open app with `allowAudioPlaybackCapture="false"` | Video streams smoothly; protected audio remains silent without errors. | Test Procedure Defined |
| **MP4 Output Validity** | Record 60 seconds with `R` hotkey | MP4 file finalized cleanly; playable in VLC, Windows Media Player, and OBS with valid `moov` atom. | Test Procedure Defined |
| **OBS Window Capture** | Add CastSprint as Window Capture in OBS | Stream appears centered in OBS at 60 FPS; zero interference with gameplay. | Test Procedure Defined |
| **30-Minute Endurance** | Mirror continuous mobile gameplay for 30 minutes | Stable FPS, memory usage flat, no audio desync, no thermal crash. | Test Procedure Defined |
| **Thermal Throttling** | Trigger device heating under heavy 3D game | Android thermal listener reduces bitrate by 40%; frame rate remains stable without stutter. | Test Procedure Defined |

---

## 3. Windows Release Packaging Checklist

1. **Build Configuration**:
   - Build target: `Release` (x64) with MSVC 2022.
   - Flags: `/W4 /permissive- /utf-8 /Zc:__cplusplus /O2 /Oi /Gy`.
   - Runtime library: Static or MultiThreaded DLL (`/MD`).
2. **Metadata & Resources**:
   - Ensure `version.rc` version matches release tag (`0.2.0.0`).
   - Icon ID 101 points to `app.ico` (256x256 embedded icon).
3. **Installer Generation**:
   - Compile `installer/castsprint_installer.iss` using Inno Setup 6.
   - Installer bundles:
     - `castsprint_receiver.exe`
     - `README.md`
     - `docs/OBS_GUIDE.md`
   - Output: `CastSprint_Setup_v0.2.0_Beta_x64.exe`.
4. **Checksums**:
   - Generate SHA-256 hash:
     ```cmd
     certutil -hashfile CastSprint_Setup_v0.2.0_Beta_x64.exe SHA256
     ```

---

## 4. Android Release Packaging Checklist

1. **Build Configuration**:
   - Run `./gradlew bundleRelease` or `./gradlew assembleRelease`.
   - Ensure ProGuard / R8 rules retain MediaCodec and Protocol data classes.
2. **Permissions Audit**:
   - Verify only required permissions are present (`FOREGROUND_SERVICE_MEDIA_PROJECTION`, `RECORD_AUDIO`, `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`).
   - Zero dangerous location, contact, or camera permissions.
3. **Play Store Readiness**:
   - Review `docs/distribution/PLAY_STORE_LISTING.md`.
   - Target SDK: API 34+ compliant.
