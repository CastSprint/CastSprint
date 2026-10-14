# CastSprint for macOS — Installation, Distribution & Notarization Guide

**Target Audience:** macOS Users, Beta Testers, and Release Engineers  
**Supported OS:** macOS 14.0 (Sonoma) and macOS 15.0+ (Sequoia)  
**Supported Architectures:** Apple Silicon (M1/M2/M3/M4) native and Intel Core (x86_64)  
**Distribution Artifact:** `CastSprint-v0.2.0-macOS.dmg`  

---

## 1. User Installation Guide (Direct DMG)

### Step 1: Download and Mount the Disk Image
1. Download `CastSprint-v0.2.0-macOS.dmg` from the official [CastSprint GitHub Releases](https://github.com/CastSprint/CastSprint/releases) page.
2. Verify the SHA-256 checksum against the published `.sha256` release file:
   ```bash
   shasum -a 256 CastSprint-v0.2.0-macOS.dmg
   ```
3. Double-click the `.dmg` file to mount the disk image.

### Step 2: Drag to Applications
1. Drag the **CastSprint** app icon into the **Applications** folder shortcut.
2. Eject the disk image from Finder.

### Step 3: First Launch & macOS Gatekeeper
Because CastSprint is distributed as an independent open-source binary outside the Mac App Store:
* **For Notarized Releases:** Double-click `CastSprint.app` in `/Applications`. When macOS displays *"CastSprint was downloaded from the internet. Are you sure you want to open it?"*, click **Open**.
* **For Unsigned / Self-Built Developer Builds:**
  If macOS displays *"CastSprint cannot be opened because the developer cannot be verified"*:
  1. Open **System Settings** -> **Privacy & Security**.
  2. Scroll to the **Security** section and click **Open Anyway**.
  3. Alternatively, remove the Gatekeeper quarantine attribute via Terminal:
     ```bash
     xattr -d com.apple.quarantine /Applications/CastSprint.app
     ```

---

## 2. First-Time System Permissions on macOS

To capture USB video and digital audio, macOS requires user authorization:

1. **Camera Permission (`NSCameraUsageDescription`):**
   * **Prompt:** *"CastSprint requires access to USB video capture devices to mirror your iPhone or iPad screen with low latency."*
   * **Why it is needed:** Apple’s `AVFoundation` security architecture classifies all external video input devices (including CoreMediaIO screen capture streams from USB-connected iPhones) under the Camera permission category.
   * **Action:** Click **OK** when prompted.
2. **Microphone Permission (`NSMicrophoneUsageDescription`):**
   * **Prompt:** *"CastSprint accesses digital audio from your USB-connected iPhone or iPad to stream gameplay audio directly to your Mac."*
   * **Action:** Click **OK** when prompted.
3. **Local Network Permission (`NSLocalNetworkUsageDescription`):**
   * Required when using the Mac as a wireless receiver for Android or iPhone Wi-Fi streaming.

---

## 3. Developer ID Code Signing & Notarization Workflow

Release engineers must follow Apple's modern `notarytool` workflow for public distribution:

### Step 1: Build & Package the Application
```bash
./scripts/package_macos.sh
```

### Step 2: Sign with Developer ID Application Certificate & Hardened Runtime
```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"

codesign --deep --force --options runtime \
    --entitlements apps/macos/CastSprintMac/CastSprintMac.entitlements \
    --sign "${CODESIGN_IDENTITY}" \
    apps/macos/CastSprintMac/CastSprint.app

# Verify signature validity
codesign --verify --deep --strict --verbose=2 apps/macos/CastSprintMac/CastSprint.app
```

### Step 3: Package the Signed Disk Image
```bash
hdiutil create -volname "CastSprint" \
    -srcfolder apps/macos/CastSprintMac/CastSprint.app \
    -ov -format UDZO \
    dist/macos/CastSprint-v0.2.0-macOS.dmg
```

### Step 4: Submit to Apple Notary Service via `notarytool`
Store your App Store Connect API credentials securely in the macOS Keychain:
```bash
xcrun notarytool store-credentials "notarytool-profile" \
    --apple-id "developer@example.com" \
    --team-id "TEAMID1234" \
    --password "abcd-efgh-ijkl-mnop" # App-specific password
```

Submit the DMG for automated Apple notarization:
```bash
xcrun notarytool submit dist/macos/CastSprint-v0.2.0-macOS.dmg \
    --keychain-profile "notarytool-profile" \
    --wait
```

### Step 5: Staple the Notarization Ticket
Once notarization succeeds, staple the ticket to the DMG so Gatekeeper can verify it offline:
```bash
xcrun stapler staple dist/macos/CastSprint-v0.2.0-macOS.dmg

# Verify that the staple is valid
spctl --assess --type open --context context:primary-signature --verbose dist/macos/CastSprint-v0.2.0-macOS.dmg
```

---

## 4. Mac App Store Sandbox Evaluation

* **Current Status:** Distributed via Notarized Developer ID DMG.
* **Why Not Initial Mac App Store?**
  * CoreMediaIO device activation (`kCMIOProviderPropertyAllowScreenCaptureDevices`) and ADB process launching (`/opt/homebrew/bin/adb`) require capabilities that conflict with standard Mac App Store App Sandbox restrictions.
  * Forcing sandbox compliance would disable USB mirroring for Android and break seamless driverless iPhone capture.
  * Developer ID distribution with Hardened Runtime provides full security, notarization, and integrity verification without compromising multimedia performance.

---

## 5. Clean Uninstallation Guide

To completely remove CastSprint from your Mac:

```bash
# 1. Quit CastSprint if running
killall CastSprintMac 2>/dev/null || true

# 2. Delete the application bundle
rm -rf /Applications/CastSprint.app

# 3. Remove application preferences and saved settings
rm -f ~/Library/Preferences/com.castsprint.macos.plist
rm -rf ~/Library/Application\ Support/CastSprint
rm -rf ~/Library/Caches/com.castsprint.macos

# 4. Optional: Reset camera/microphone permission entries in TCC database
tccutil reset Camera com.castsprint.macos
tccutil reset Microphone com.castsprint.macos
```
