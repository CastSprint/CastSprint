# Cross-platform protocol tests

Executed on 2026-10-16:

- Android `testDebugUnitTest lintDebug assembleDebug`: PASS, 51 tasks.
- macOS `swift build -c release`: PASS.
- Earlier same-revision native suites: protocol 178, session 19, sync 10 checks; zero failures.

Not executed: Android-to-desktop socket integration, TLS interoperability, Windows/Linux native build, physical decoder/render/audio, invalid/expired token and replay tests. These remain required.
