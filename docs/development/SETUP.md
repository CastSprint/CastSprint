# Development Setup

## Prerequisites

| Component | Version used / required |
|---|---|
| JDK | 17 (Temurin/OpenJDK) |
| Android SDK | Platform 36, Build-Tools 36.x (`compileSdk = targetSdk = 36`, `minSdk = 29`) |
| Gradle | 8.13 via wrapper (`apps/android/gradlew`) |
| Android Gradle Plugin / Kotlin | 8.13.2 / 2.0.21 |
| Windows | Windows 10/11 x64, Visual Studio 2022 (Desktop C++ workload) with Windows 10/11 SDK |
| CMake | ≥ 3.22 (VS-bundled is fine) |
| Android NDK | Not needed yet (only when profiling justifies native code) |

## Android

```bash
cd apps/android
echo "sdk.dir=/path/to/Android/sdk" > local.properties   # or set ANDROID_HOME
./gradlew assembleDebug testDebugUnitTest lintDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.castsprint.android/.MainActivity
```
Or open `apps/android` in Android Studio and press Run.

## Windows (Developer PowerShell for VS 2022)

```powershell
cmake -S . -B build/win -G "Visual Studio 17 2022" -A x64
cmake --build build/win --config Debug
ctest --test-dir build/win -C Debug --output-on-failure
.\build\win\apps\windows\Debug\castsprint_receiver.exe
```
`castsprint_receiver.exe --smoke-test` creates a hidden window, renders 3 frames and exits 0/1.

## Protocol library on any host (macOS / Linux)

```bash
cmake -S . -B build/host -DCMAKE_BUILD_TYPE=Debug
cmake --build build/host
ctest --test-dir build/host --output-on-failure
```
The Windows app is skipped automatically on non-Windows hosts.

## Licensing
See [LICENSING.md](LICENSING.md) — no license chosen yet.
