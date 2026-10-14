# CastSprint — Apple Permissions, Entitlements & Security Architecture

**Scope:** macOS Host Application (`CastSprintMac`), iOS Client Application (`CastSprintIOS`), and ReplayKit Broadcast Extension (`LegacyBroadcastExtension`)  
**Compliance Standard:** Apple App Store Review Guidelines (Sections 2.5, 5.1, 5.2) & Apple Hardened Runtime  

---

## 1. Overview of Platform Permissions

CastSprint adheres to a strict principle of **minimal privilege**:
- Permissions are requested strictly on-demand when the user activates a feature.
- No permissions are requested on first launch unless an active connection or discovery requires it.
- Zero analytics, advertising, or tracking SDKs are embedded in any CastSprint binary.
- All network communication is restricted to the user's private local subnet (LAN); no external servers are contacted.

---

## 2. iOS Client Permissions & Purpose Strings (`apps/ios/CastSprintIOS/Info.plist`)

| Key | User-Facing Purpose String | Technical Justification | App Store Guideline Reference |
|:---|:---|:---|:---|
| **`NSLocalNetworkUsageDescription`** | *"CastSprint uses your local Wi-Fi network to discover and stream gameplay video and audio directly to your Windows PC or Mac receiver without using any cloud servers."* | Required to establish peer-to-peer TCP socket connections over port `27183` on the local Wi-Fi subnet. | Guideline 5.1.1 (Data Collection & Storage) |
| **`NSBonjourServices`** | `<array><string>_castsprint._tcp</string></array>` | Advertised service identifier allowing `NWBrowser` to locate CastSprint Windows and macOS receivers automatically. | Guideline 2.5.1 (Public APIs) |
| **`NSCameraUsageDescription`** | *"CastSprint uses your camera solely to scan the desktop pairing QR code displayed by CastSprint on your PC or Mac."* | Required for `AVCaptureSession` in the optional QR scanner. Camera frames are processed strictly in-memory for barcode detection and are never recorded or transmitted. | Guideline 5.1.2 (Data Use & Sharing) |
| **`NSMicrophoneUsageDescription`** | *"CastSprint uses the microphone only if you explicitly enable voice commentary to stream alongside your game audio."* | Required only when the user explicitly turns on the "Microphone Commentary" toggle. Internal game audio is captured directly without microphone access. | Guideline 5.1.1 (Data Collection) |

### iOS Entitlements (`apps/ios/CastSprintIOS/CastSprintIOS.entitlements`)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Group required for IPC between containing app and ReplayKit extension -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.castsprint.ios</string>
    </array>
</dict>
</plist>
```

---

## 3. iOS ReplayKit Broadcast Extension (`apps/ios/LegacyBroadcastExtension/Info.plist`)

Apple enforces specialized sandboxing and memory limits on Broadcast Upload Extensions:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.broadcast-services-upload</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).SampleHandler</string>
    <key>RPBroadcastProcessMode</key>
    <string>RPBroadcastProcessModeSampleBuffer</string>
</dict>
```

### Security & Compliance Safeguards:
1. **Explicit User Initiation:** The broadcast extension cannot start capturing silently. Apple’s system modal (`RPSystemBroadcastPickerView`) alerts the user and displays a 3-second countdown.
2. **System Recording Indicator:** A persistent red pill or Dynamic Island broadcast glyph is displayed by iOS throughout the entire capture session.
3. **DRM Protection:** FairPlay / HDCP protected video (Netflix, Disney+, Apple TV+) is blocked at the hardware level by iOS; the extension receives blank frames, preventing unauthorized recording of copyright-protected video.
4. **Zero Background Abuse:** The extension contains zero unauthorized background modes (`audio`, `location`, `voip`). When the broadcast stops, the extension process terminates immediately.

---

## 4. macOS Receiver Permissions & Entitlements (`apps/macos/CastSprintMac/Info.plist`)

| Key | User-Facing Purpose String | Technical Justification |
|:---|:---|:---|
| **`NSCameraUsageDescription`** | *"CastSprint requires access to USB video capture devices to mirror your iPhone or iPad screen with low latency."* | In macOS security architecture, CoreMediaIO external video capture devices (including USB-connected iOS devices) are governed by the Camera TCC permission. |
| **`NSMicrophoneUsageDescription`** | *"CastSprint accesses digital audio from your USB-connected iPhone or iPad to stream gameplay audio directly to your Mac."* | Required to receive digital PCM audio from the connected iOS device's USB audio endpoint. |
| **`NSLocalNetworkUsageDescription`** | *"CastSprint discovers and receives screen mirroring connections from your mobile devices over your local Wi-Fi network without any cloud servers."* | Required to bind `NWListener` on TCP port 27183 and advertise `_castsprint._tcp` via Bonjour. |
| **`NSBonjourServices`** | `<array><string>_castsprint._tcp</string></array>` | Bonjour mDNS service advertised across the local subnet. |

### macOS Hardened Runtime Entitlements (`CastSprintMac.entitlements`)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Access USB camera / screen capture endpoints via AVFoundation -->
    <key>com.apple.security.device.camera</key>
    <true/>
    <!-- Access USB audio input endpoints -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <!-- Inbound & Outbound LAN connections -->
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <!-- User-selected file save permissions for MP4 recordings (~/Movies/CastSprint) -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

---

## 5. Security & Privacy Validation Checklist

- [x] **Zero Telemetry:** No analytics, tracking tokens, or crash reporting SDKs linked.
- [x] **Zero Cloud Relay:** Video and audio never leave the private Wi-Fi subnet or physical USB cable.
- [x] **Verified Pairing:** Desktop receiver displays a 4-digit PIN and SHA-256 TLS fingerprint to prevent unauthorized connection hijacking.
- [x] **No Hidden Recording:** System status bar displays active recording indicator at all times.
- [x] **Local Disk Recording by User Request Only:** Video is never recorded to disk unless the user explicitly clicks the Record button or presses `R`.
- [x] **Safe Memory Deallocation:** Uncompressed frame buffers and memory buffers are freed immediately on the capture queue to maintain zero persistent trace.
- [x] **Hardened Runtime Compliance:** macOS binaries are compiled with Apple Hardened Runtime, preventing dynamic library injection and memory modification attacks.
