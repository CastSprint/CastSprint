# Android APK feature audit

Revision: `8c7ba57`, app `com.castsprint.android` 0.3.3 (8).

| Feature | Status | Evidence |
|---|---|---|
| MediaProjection H.264 | BUILD_ONLY | Gradle test/lint/assemble pass |
| AudioPlaybackCapture AAC | BUILD_ONLY | source and unit build; no audible hardware run |
| USB Gaming via ADB reverse | IMPLEMENTED_UNTESTED | verified tunnel check, token provisioning, app launch |
| USB Quick Mirror | IMPLEMENTED_UNTESTED | macOS app-less screenrecord path |
| Wi-Fi TLS | FAILED | Android pins TLS; desktop servers are not interoperable TLS endpoints |
| mDNS discovery | IMPLEMENTED_UNTESTED | NsdManager resolution present |
| Manual pairing | IMPLEMENTED_UNTESTED | host/port/fingerprint/token UI present |
| QR scanner | MISSING | no camera flow implemented |

The APK requests MediaProjection consent and never substitutes microphone capture. `RECORD_AUDIO` remains because Android playback capture requires audio authorization on supported versions.
