# Creator Ready Status

Version: 0.3.0 (build 5)

Implemented: stable clean gameplay window, automatic source-aspect resizing, fixed canvas presets, manual layout mode, independent output telemetry, deferred audio permission, and muxed-source diagnostics.

Build verification: macOS app target compiles. XCTest is blocked by the machine's Command Line Tools-only installation, which cannot resolve XCTest. Real OBS recordings, isolated game audio, ten rotations, Streamlabs, and long performance testing remain unverified. Release verdict: **IMPLEMENTED_UNTESTED**, not creator-ready PASS.

Installed locally at `/Applications/CastSprint.app`. The arm64 executable is ad-hoc signed with the declared camera, audio-input, user-selected-file, and network client/server entitlements. Its verified SHA-256 is `a04d10ed6b7f96d855f82fc98a5df3a6753c15b176ba64f89deb8eed9b4b5d5a`. The prior 0.2.3 application is backed up under `~/Library/Application Support/CastSprint/Backups/2026-10-15-v0.2.3-before-v0.3.0/`.
