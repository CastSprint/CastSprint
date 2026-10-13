# Testing

| Suite | Command | Platform |
|---|---|---|
| Protocol codec (C++) | `ctest --test-dir build/host --output-on-failure` | any |
| Protocol codec with sanitizers | configure with `-DCMAKE_CXX_FLAGS="-fsanitize=address,undefined"` | macOS/Linux |
| Kotlin protocol + golden vector | `cd apps/android && ./gradlew testDebugUnitTest` | any with JDK 17 |
| Android compile + lint | `./gradlew assembleDebug lintDebug` | any |
| Windows startup smoke test | `ctest -C Debug -R windows_app_smoke` | Windows |

Golden vectors in `PROTOCOL.md §8` must be identical in the C++ and Kotlin test suites.
