# Android USB Result

Status: **BLOCKED**

Date: 2026-10-15

- `adb`: 37.0.1 at `/opt/homebrew/bin/adb`
- `scrcpy`: 5.0.1 at `/opt/homebrew/bin/scrcpy`
- `adb devices -l`: no devices
- macOS USB inventory: no identifiable Android device
- CastSprint app target build: passed
- Real Home Screen/gameplay/rendered FPS: not tested; no device was attached

Source audit found and corrected two pre-device faults: Android VideoToolbox output dimensions were hard-coded to 1920×1080 instead of using the stream SPS, and `adb screenrecord` stderr was discarded. The current implementation now derives native dimensions from the H.264 format description and reports real process failures.

Next evidence gate: attach and unlock the phone, enable USB debugging, accept its RSA authorization prompt, and confirm it appears as `device` in `adb devices -l`. Then run the scrcpy baseline followed by CastSprint Home Screen, game, rotation, and reconnect tests.
