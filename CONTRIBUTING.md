# Contributing

1. Read [docs/architecture/OVERVIEW.md](docs/architecture/OVERVIEW.md) and
   [PROTOCOL.md](docs/architecture/PROTOCOL.md).
2. Keep layers separate: capture, encode, transport, decode, render, record, UI.
3. C++: C++20, RAII for every native resource (`ComPtr`, unique handles), no raw `new/delete`,
   builds warning-free at `/W4 /WX` (MSVC) and `-Wall -Wextra -Wconversion -Werror`.
4. Kotlin: official style, no new dependencies without discussion.
5. Protocol changes: update `PROTOCOL.md`, the C++ codec, the Kotlin codec, and golden vectors
   together. Breaking changes bump the protocol version.
6. Never fake measurements. Performance claims need reproducible numbers and named hardware.
7. Do not copy code from scrcpy or other projects with incompatible licenses.
8. Run all tests listed in [docs/testing/TESTING.md](docs/testing/TESTING.md) before opening a PR.
