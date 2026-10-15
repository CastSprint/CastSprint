# Reinstall Verification — 2026-10-15

## Installed build

- Path: `/Applications/CastSprint.app`
- Version/build: `0.2.1` / `2`
- Bundle identifier: `com.castsprint.macos`
- Architecture: arm64
- Configuration: release
- Source identity: `b1297318144feed42cb25a544e037424b208d288-dirty`
- Signed executable SHA-256: `321f6c09b2b90d322b5b2ba3e60fc4fb67ed9347b02c38bb94dcba92a64fc685`
- Signature: valid ad-hoc signature

The built, staged, installed and running executable hashes were compared byte-for-byte. The running process path was `/Applications/CastSprint.app/Contents/MacOS/CastSprintMac`.

## Rollback

The previous 0.2.0 application is preserved at:

`~/Library/Application Support/CastSprint/Backups/2026-10-15-v0.2.0-before-v0.2.1/CastSprint.app`

Previous executable SHA-256: `0679e65435979ad1be9a22dd9aabaf80319a7f1364043cbc78fc65ab4ebfbdbc`.

No recordings, preferences, privacy databases or unrelated files were modified. Because both builds are ad-hoc signed and the code directory changed, macOS may legitimately request capture/audio permission again.

## Smoke test

- Installed application launch: PASS.
- Main SwiftUI window: PASS.
- Process identity/hash: PASS.
- Idle CPU snapshot: approximately 4.3% shortly after launch; longer stabilized measurement pending.
- iPhone discovery/capture/presentation: NOT_TESTED because no iPhone was attached/enumerated.
