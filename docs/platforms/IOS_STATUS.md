# iOS status

- Bonjour receiver discovery: **IMPLEMENTED_UNTESTED**; resolved service addresses replace the invalid `127.0.0.1` value.
- ReplayKit broadcast video/app audio encode: **IMPLEMENTED_UNTESTED**.
- Pairing token handshake: **IMPLEMENTED_UNTESTED**.
- Microphone: disabled in sample handling, picker UI and Info.plist.
- LAN encryption: **MISSING**.
- Swift/package test: **BLOCKED** by incomplete local Apple toolchain (SwiftUI macros/XCTest).
- Signed physical iPhone build: **BLOCKED** by unavailable full Xcode/signing context.
- iPhone USB is a macOS receiver feature, not proof that the iOS Wi-Fi sender works.

Foreground-app capture must continue to use ReplayKit Broadcast Upload Extension semantics; switching to a game cannot depend on the container app remaining active.
