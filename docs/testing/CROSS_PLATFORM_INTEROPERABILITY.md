# Cross-platform interoperability

## Executed

- Native C++ protocol: 178 checks PASS.
- Native C++ session: 19 checks PASS.
- Native C++ A/V sync: 10 checks PASS.
- Android unit/lint/APK build: PASS.
- macOS release compile: PASS.

## Not executed

No physical Android/iOS LAN sender was connected to each desktop receiver in this audit. No Windows/Linux host existed. Therefore video decode, audio playback, rotation, reconnect, TLS, OBS recording and A/V synchronization are not verified cross-platform.

## Required matrix

Each Android and iOS sender must be tested against macOS, Windows and Linux using: correct/wrong/expired token, 720p/1080p, portrait/landscape, AAC config change, 10-minute gameplay, network interruption, receiver restart, bounded memory, and a 60-second OBS recording. Capture packet traces for security and preserve logs/checksums as evidence.
