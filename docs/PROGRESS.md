# Progress

## Phase 1 — Foundation (2026-10-13)

| Item | Status | Verified on |
|---|---|---|
| Protocol v1 spec (`docs/architecture/PROTOCOL.md`) | Done | — |
| C++20 protocol codec (`native/protocol`) | Done | macOS arm64, AppleClang 21, `-Wall -Wextra -Wconversion -Werror` |
| Protocol tests (round-trip, invalid packets, versions, golden vector) | Pass | macOS (CTest); also run under ASan/UBSan |
| Kotlin protocol subset + JVM tests (shared golden vector) | Pass | `./gradlew testDebugUnitTest` |
| Android app (`com.castsprint.android`) assemble + lint | Pass | AGP 8.13.2, Gradle 8.13, JDK 17 |
| Windows Win32 + D3D11 receiver shell | Written, **not compiled locally** | Pending: Windows/MSVC (CI `windows.yml`) |
| Windows `--smoke-test` startup test | Written, **not run locally** | Pending: Windows |
| GitHub Actions workflows | Written, not yet run | Needs push |
| License | **Decision pending** | see `docs/development/LICENSING.md` |

## Next (Phase 2)
See [ROADMAP.md](ROADMAP.md).
