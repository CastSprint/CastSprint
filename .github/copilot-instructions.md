# CastSprint — AI Assistant Instructions

Applies to all AI coding assistants (Copilot, Antigravity, Codex).

## Product constraints (non-negotiable)
Free forever; no accounts, ads, watermarks, cloud backend, telemetry. Local USB/LAN only; core
mirroring works offline. Android 10+ sender, Windows 10/11 x64 receiver.

## Stack
- Android: Kotlin, framework SDK, Gradle Kotlin DSL, MediaProjection, MediaCodec,
  AudioPlaybackCapture, foreground services. NDK only when measurements justify it.
- Windows: C++20, Win32, Direct3D 11/DXGI, Media Foundation, WASAPI, CMake/MSVC.
- Forbidden: Electron, Chromium/WebView UI, Node.js runtime, undocumented Android APIs,
  permission bypasses, code copied from scrcpy.

## Rules
1. Correctness before optimization; real implementations, not mockups.
2. Keep capture / encode / transport / decode / render / record / UI separate.
3. RAII for every native resource; deterministic shutdown; no raw owning pointers.
4. Bounded queues; no busy-waits or sleep-polling; no unbounded allocations.
5. Validate all network input per `docs/architecture/PROTOCOL.md` before allocating.
6. Protocol changes must update spec + C++ codec + Kotlin codec + golden vectors together.
7. Never fabricate benchmarks or hardware capabilities.
8. Warnings are errors (`/W4 /WX`, `-Wall -Wextra -Wconversion -Werror`, Kotlin `allWarningsAsErrors`).
9. Update `docs/PROGRESS.md` when completing work; state exactly what was and wasn't verified.
10. Never push to GitHub or pick a license without maintainer approval.

## Key paths
`native/protocol` (codec) · `apps/windows/src` · `apps/android/app/src/main/java/com/castsprint/android`
· `docs/architecture/*`
