# Cross-platform feature audit

Audit baseline: `main` at `e9bb263` (2026-10-16). Status words are evidence levels, not roadmap claims.

| Capability | macOS | Windows | Linux | Android | iOS |
|---|---|---|---|---|---|
| Native build on current Mac | BUILD_ONLY | BLOCKED | BLOCKED | BUILD_ONLY | BLOCKED |
| USB display capture | VERIFIED_HARDWARE (iPhone evidence supplied) / IMPLEMENTED_UNTESTED (Android) | MISSING | MISSING | n/a sender | n/a sender |
| LAN video | IMPLEMENTED_UNTESTED | PARTIAL | STUB | BUILD_ONLY | IMPLEMENTED_UNTESTED |
| LAN game audio | IMPLEMENTED_UNTESTED | PARTIAL | STUB | BUILD_ONLY | IMPLEMENTED_UNTESTED |
| Authenticated pairing | IMPLEMENTED_UNTESTED | IMPLEMENTED_UNTESTED | IMPLEMENTED_UNTESTED | BUILD_ONLY | IMPLEMENTED_UNTESTED |
| Encrypted LAN media | MISSING | STUB | MISSING | BUILD_ONLY client | MISSING |
| OBS-ready window/output | VERIFIED_HARDWARE from supplied screenshots | IMPLEMENTED_UNTESTED | MISSING | n/a | n/a |

Key result: the Apple USB path visibly works, but the repository is not a production-ready five-platform product. Windows transport encryption is not actually applied to socket I/O; Linux has no decoder, renderer, or audio sink; Apple LAN transport is plaintext.

Changes in this audit fixed the iOS discovery address, aligned the six-digit pairing token, added macOS AAC decoding, removed iOS microphone capture, and made Linux fail honestly instead of labeling encoded H.264/audio as decoded/played.
