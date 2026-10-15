# Complete Source Audit — 2026-10-15

## Audited revisions

- CastSprint: branch `audit/full-product-completion`, commit `72c155b34aa24efee86559097be8486dc3ff73f5`, five commits ahead of `origin/audit/full-product-completion` when this audit began.
- MirrorPhone: branch `main`, commit `d77fbc38dcf709552d1f066a000de66e0638c3fc` (2026-08-31), cloned from `https://github.com/tacshi/MirrorPhone.git`.
- CastSprint had pre-existing uncommitted macOS renderer/UI/telemetry work and modified DMG artifacts. It was preserved and audited in place; the repository was not reset.
- The local checkpoint branch `checkpoint/before-black-screen-fix` points at `72c155b`. The pre-existing dirty worktree is visible in Git and was not hidden in a stash.

## Installed application identity

`/Applications/CastSprint.app` was inspected before any replacement. It reports bundle ID `com.castsprint.macos`, version `0.2.0` build `1`, arm64 executable, and an ad-hoc signature. Its executable SHA-256 was `1377d0ff0cb2d424402ff1190ae66cfe7a605514a8d40a8d50be998a7e014fa2`.

The installed binary does not contain a reproducible source revision marker, and its hash does not identify a Git commit. Therefore its exact source revision is **UNKNOWN**. It was not overwritten during this audit.

## Source topology and evidence

| Area | Concrete implementation | Audit status |
|---|---|---|
| macOS iPhone USB | `IPhoneUSBDisplayCaptureProvider.swift`, `IPhoneUSBCaptureSession.swift` | Real `.muxed` AVFoundation discovery/capture; hardware verification pending |
| macOS rendering | `MetalVideoRenderer.swift`, `MetalViewRepresentable.swift` | Repaired to one CAMetalLayer ownership model; release build passes |
| macOS Android USB | `AndroidScreenrecordSession.swift`, `VideoToolboxDecoder.swift` | Real ADB `screenrecord` route; no device attached during audit |
| macOS LAN receiver | `NetworkStreamReceiver.swift`, `LanDiscoveryAdvertiser.swift` | Implemented; end-to-end phone test pending |
| Android Wi-Fi sender | Kotlin MediaProjection, MediaCodec, AudioPlaybackCapture, transport modules | Unit/lint/build pass; physical stream not rerun |
| iOS Wi-Fi sender | ReplayKit/ScreenCaptureKit-gated capture, VideoToolbox, Network.framework | Source present; signing/device verification pending |
| Windows | C++20 Win32, Media Foundation, D3D11, WASAPI | Source present; not buildable on this macOS host |
| Linux | C++20 receiver with FFmpeg/SDL-dependent backend | Source present; not buildable on this macOS host; `cmake` absent |

## Build and test evidence from this audit

- macOS `swift build`: PASS.
- macOS release build and DMG packaging: PASS.
- macOS `swift test`: BLOCKED by this host's Command Line Tools XCTest resolution (`unable to resolve module dependency: XCTest`). This is an environment/toolchain failure, not a passing test run.
- Android `./gradlew clean test lint assembleDebug`: PASS.
- MirrorPhone `swift build -c release`: PASS.
- MirrorPhone tests: FAILED TO COMPILE under Swift 6.4 because `AndroidClipboardTests.swift` contains an expression the compiler cannot type-check in reasonable time.
- Native C++: NOT_RUN because `cmake` is not installed.
- Device inventory: no iOS device returned by `xcrun devicectl`; no Android device returned by `adb devices -l`.

## Known defects and risks

1. Real iPhone/Android frames, internal audio, OBS, Streamlabs, latency and endurance are not verified in this run.
2. Existing documentation contains historical performance and hardware claims that are not supported by evidence collected in this audit. Treat those as stale until rerun.
3. The installed app lacks a source revision marker.
4. CastSprint's source uses architecture and behavior learned from MirrorPhone; public redistribution permission still needs a written license/permission review.
5. Windows and Linux artifacts cannot be validated on this Apple Silicon host.

## Generated artifacts

- `dist/macos/CastSprint-v0.2.0-macOS.dmg`: SHA-256 `705f74ac42a7fc3716b8a52dbc59ece8c5211007b0d9bffbd5f21d09791e2678`.
- `dist/android/CastSprint-Android-debug.apk`: SHA-256 `939c2067f88b592649cc8bcbc27c737df3c7c13b1c4f6c97ca778a30b8860d7d`.
- Generated macOS executable: SHA-256 `0679e65435979ad1be9a22dd9aabaf80319a7f1364043cbc78fc65ab4ebfbdbc`.

These artifacts are build-validated, not hardware-certified.
