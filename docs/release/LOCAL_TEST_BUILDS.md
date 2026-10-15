# Local Test Builds

Date: 2026-10-15

## Current source

- Branch: `main`
- Starting revision: `58dd4c1fb58feeb16438dc40f45597ee6eedbdb6`
- Local changes were preserved.
- `swift build --product CastSprintMac`: passed (arm64 host)
- XCTest: blocked because only `/Library/Developer/CommandLineTools` is installed; that SDK cannot resolve XCTest. Full Xcode is absent.

## Installed application

- Path: `/Applications/CastSprint.app`
- Version observed before this change set: 0.2.3 (build 4)
- Architecture: arm64
- Signature: ad-hoc
- Executable SHA-256 observed: `354feaccd37932d551c3286ff16d2f234595f37bdab97c384f07b597ac8f57b7`

The installed app was not replaced during the blocked Android device check. A fresh package/install/hash verification must follow successful device-level validation.
