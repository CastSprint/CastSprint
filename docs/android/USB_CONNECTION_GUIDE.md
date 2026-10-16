# Android USB connection guide

## USB Gaming — recommended

1. Install matching CastSprint Android 0.3.3 and macOS 0.3.3 test builds.
2. Enable Developer Options and USB Debugging; connect a data cable and approve the Mac.
3. In desktop CastSprint select `Android — USB Gaming` and Start.
4. Desktop verifies `adb reverse tcp:27183 tcp:27183`, opens the APK, and provisions a six-digit session token.
5. In the APK press Start and approve Android's Screen Capture prompt.

Video and permitted playback audio use the USB-only reverse tunnel. Failure to verify the reverse mapping aborts the session.

## USB Quick Mirror

Select `Android — USB Quick Mirror`. This runs app-less ADB screenrecord video. Game audio is unsupported. It never silently installs or launches the APK.
