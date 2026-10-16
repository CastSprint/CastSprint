# Actual source evidence

| Finding | Source evidence | Result |
|---|---|---|
| macOS LAN was plaintext | `NetworkStreamReceiver.swift`: `NWParameters(tls: nil, ...)` | release blocker |
| iOS LAN was plaintext | `NetworkTransportSink.swift`: `NWParameters(tls: nil, ...)` | release blocker |
| iOS discovery used loopback | `BonjourReceiverBrowser.swift` previously emitted `127.0.0.1` | fixed with `NetService` address resolution |
| Pairing token was not passed | macOS coordinator called receiver without token; Windows/Linux compared full device name | fixed; sender uses `deviceName|token`, receivers extract token |
| macOS treated AAC as PCM | coordinator passed every audio payload to PCM scheduling | fixed with negotiated AAC/PCM path and `AVAudioConverter` |
| iOS could transmit microphone | ReplayKit `.audioMic`, UI toggle and picker button | disabled; app audio remains |
| Windows TLS was cosmetic | credentials are acquired, but `HandleClient` uses raw `recv`/`send` | STUB, not TLS |
| Linux decode was false success | `DecodedVideoFrame.yuvData = frame.data` | fixed to fail closed |
| Linux audio was false success | `PlayFrame` returned true without an output API | fixed to fail closed |

Executed evidence on 2026-10-16:

- macOS `swift build -c release`: PASS (arm64 host).
- Android `testDebugUnitTest lintDebug assembleDebug`: PASS, 51 Gradle tasks.
- Native protocol/session/sync direct Clang runs: 178/19/10 checks, zero failures.
- macOS `swift test`: BLOCKED because the selected Command Line Tools installation cannot resolve `XCTest`.
- iOS Swift build/device build: BLOCKED because full Xcode and signing are unavailable.
- CMake targets: BLOCKED because `cmake` is not installed on this host.
