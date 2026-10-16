# Android status

- Gradle unit tests, lint and debug assembly: **BUILD_ONLY — PASS** (51 tasks).
- APK: `apps/android/app/build/outputs/apk/debug/app-debug.apk` when produced by the verified build.
- Wi-Fi MediaProjection/H.264 and AudioPlaybackCapture sender: **BUILD_ONLY**.
- TLS/pinning client: **BUILD_ONLY**, but incompatible with current plaintext Apple/Linux receivers and incomplete Windows TLS server.
- Android USB on macOS: **IMPLEMENTED_UNTESTED**; requires ADB-authorized physical-device run.
- Real gameplay, rotation, audio, reconnect and OBS: **BLOCKED/UNTESTED** in this audit.

No microphone fallback is accepted. Games/OS versions that disallow playback capture must keep video working and report audio unavailable.
