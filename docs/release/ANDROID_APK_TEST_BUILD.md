# Android APK test build

- Status: **BUILD_ONLY**
- Source revision: `8c7ba57f3c72cf95f31786945888f643c8dd931d`
- Package: `com.castsprint.android`
- Version: `0.3.3` (8)
- SDK: min 29, target 36, compile 36
- Artifact: `dist/android/0.3.3/CastSprint-Android-0.3.3-debug.apk`
- SHA-256: `deac9e260e88b4aac490ca67e0578ff9a8cd4192e5d13f37e73a663ef0e977cd`
- Signature: Android Debug, RSA 2048; v2 verified
- Signer certificate SHA-256: `0a980b6123dbe07395603f4b0fddfc89d49dd32aab512538aa8315c4209225d6`
- Install result: **BLOCKED**, no ADB device connected

Rollback: retain the previously installed APK; when a device is present, record its current version before `adb install -r`. This debug build must not be published as a production release.
