# macOS status

- Build: **BUILD_ONLY — PASS**, `swift build -c release` on Apple Silicon.
- Tests: **BLOCKED**, current Command Line Tools cannot resolve XCTest.
- iPhone USB video/OBS: **VERIFIED_HARDWARE** from owner-supplied screenshots (2vuy, changing display, gameplay window, OBS capture).
- Android USB: **IMPLEMENTED_UNTESTED** in this audit.
- LAN pairing: **IMPLEMENTED_UNTESTED** after token validation fix.
- LAN AAC: **IMPLEMENTED_UNTESTED** after AVAudioConverter integration.
- LAN encryption: **MISSING**.
- Public release: **BLOCKED** by transport security and current signing/notarization evidence.

Performance screenshots show CastSprint around 29–35% CPU, OBS around 44–48%, and WindowServer around 38% CPU/44–60% GPU during duplicated live composition. WindowServer is the macOS compositor; high use is expected when CastSprint, its clean window, OBS preview, and Activity Monitor all redraw, but the combined load is not lightweight and still needs controlled profiling.
