# Android to macOS compatibility

| Route | Status |
|---|---|
| USB Gaming APK video/audio | IMPLEMENTED_UNTESTED |
| USB Quick Mirror video | IMPLEMENTED_UNTESTED |
| Wi-Fi video/audio | FAILED (TLS mismatch) |
| OBS output | BLOCKED pending Android hardware |

macOS 0.3.3 now exposes separate USB entries, verifies ADB reverse, provisions the session token, launches the APK, accepts H.264/AAC, and retains the clean OBS window. Build/package verification passed on arm64. No Android was connected, so this is not hardware verification.
