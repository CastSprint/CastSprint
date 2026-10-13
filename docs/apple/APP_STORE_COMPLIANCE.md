# Apple App Store Compliance & Security Architecture

CastSprint is engineered to meet Apple’s strictest standards for privacy, platform integrity, and App Store Review Guidelines for both the **iOS App Store** and the **Mac App Store** / Notarized Developer ID distribution.

---

## 1. Compliance with App Store Review Guidelines

### Guideline 2.5.1 — Public APIs Only
- **Policy**: Apps may only use documented, public APIs and must not link against private frameworks or call private symbols.
- **Implementation in iOS Client**:
  - Screen capture utilizes exclusively standard `ReplayKit` (`RPBroadcastSampleHandler`) and `ScreenCaptureKit`.
  - Video encoding uses documented `VideoToolbox` APIs (`VTCompressionSessionCreate`, etc.).
  - Networking uses official `Network.framework` (`NWConnection`).
  - **Zero private APIs** are referenced in the iOS application codebase.

### Guideline 5.2.5 — Screen Recording & User Consent
- **Policy**: Screen recording apps must never initiate capture silently. The user must explicitly consent to starting and stopping the capture session.
- **Implementation**:
  - CastSprint initiates recording exclusively through the system-provided `RPSystemBroadcastPickerView`.
  - The iOS system displays a confirmation dialog alerting the user that screen content and audio will be captured.
  - The system status bar displays the active recording indicator (red pill or dynamic island broadcast symbol) throughout the session.

### Guideline 5.1.1 — Data Privacy & Tracking
- **Policy**: Apps must provide complete transparency regarding collected data and obtain consent for sensitive hardware access.
- **Implementation**:
  - **Zero Telemetry**: CastSprint includes no analytics SDKs, advertising frameworks, or crash reporting aggregators.
  - **Zero Cloud Storage**: All media frames remain strictly within the user's local network or physical USB connection.
  - **Zero Login**: No user credentials, accounts, or personal identities are collected or retained.

---

## 2. Privacy Manifest & Info.plist Disclosures

### iOS Client (`Info.plist`)
```xml
<key>NSMicrophoneUsageDescription</key>
<string>CastSprint uses the microphone only if you choose to include voice commentary with your game stream. Internal game audio is captured directly.</string>

<key>NSLocalNetworkUsageDescription</key>
<string>CastSprint connects directly to your Windows or Mac receiver over your local Wi-Fi network.</string>

<key>NSBonjourServices</key>
<array>
    <string>_castsprint._tcp</string>
</array>
```

### macOS Receiver Entitlements (`CastSprintMac.entitlements`)
To support native iPhone USB capture and local networking within the App Sandbox:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required to access USB video capture devices (iPhones) via AVFoundation -->
    <key>com.apple.security.device.camera</key>
    <true/>
    <!-- Required to receive audio from USB devices -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <!-- Required for local network server and mDNS discovery -->
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <!-- Required to save MP4 recordings to user-selected folder -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

---

## 3. macOS Distribution & Notarization

For distribution outside the Mac App Store (Direct DMG / Homebrew Cask):
1. Binaries are signed with a Developer ID Application certificate.
2. Hardened Runtime (`--options runtime`) is enabled.
3. Packages are submitted to Apple's Notary Service via `xcrun notarytool`.
4. Tickets are stapled using `xcrun stapler staple`.
