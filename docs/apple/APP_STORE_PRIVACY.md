# CastSprint iOS — App Store Privacy Details (Privacy Nutrition Label)

This document specifies the accurate App Store Privacy information for **CastSprint for iOS & iPadOS** in App Store Connect.

---

## 1. App Privacy Nutrition Label Summary

| Category | Status | Details |
|:---|:---|:---|
| **Data Used to Track You** | **None** | CastSprint does not track users across apps or websites. |
| **Data Linked to You** | **None** | No personal data, identities, accounts, or analytics are linked. |
| **Data Not Linked to You** | **None** | No data is collected, stored, or sent to remote servers. |
| **Data Collected** | **Data Not Collected** | Select "Data Not Collected" in App Store Connect. |

---

## 2. Hardware & Permission Disclosures

### A. Local Network Access (`NSLocalNetworkUsageDescription`)
- **App Store Purpose String**:
  > *"CastSprint uses your local Wi-Fi network to discover and stream gameplay video and audio directly to your Windows PC or Mac receiver without using any cloud servers."*
- **Technical Use**: Discovers desktop receivers advertising Bonjour service `_castsprint._tcp` and establishes a direct peer-to-peer TCP connection over port `27183` on the user's private subnet.
- **Privacy Assurance**: No data is sent to external internet hosts or remote relays.

### B. Camera (`NSCameraUsageDescription`)
- **App Store Purpose String**:
  > *"CastSprint uses your camera solely to scan the desktop pairing QR code displayed by CastSprint on your PC or Mac."*
- **Technical Use**: Invokes `AVCaptureSession` to read QR metadata when the user explicitly taps "Scan Desktop QR Code".
- **Privacy Assurance**: Video frames from the camera are processed on-device in memory solely for barcode recognition and are never recorded, saved, or transmitted. Camera permission is optional; users can enter receiver IP and PIN manually.

### C. Microphone (`NSMicrophoneUsageDescription`)
- **App Store Purpose String**:
  > *"CastSprint uses the microphone only if you explicitly enable voice commentary to stream alongside your game audio."*
- **Technical Use**: ReplayKit passes `.audioMic` sample buffers to the audio encoder only when commentary is enabled.
- **Privacy Assurance**: Microphone audio is disabled by default. Game audio captures internal sound effects and music without requiring microphone permissions.

### D. Screen Recording (ReplayKit & ScreenCaptureKit)
- **Technical Use**: Screen video frames are captured via system-approved `RPBroadcastSampleHandler` / `SCStream` only after the user taps "Start Broadcast" in Apple's system modal.
- **Privacy Assurance**: Protected DRM content (FairPlay/HDCP) cannot be captured. An active recording indicator is shown by the system status bar at all times.

---

## 3. Third-Party Framework Audit
CastSprint links **zero third-party SDKs**:
- ❌ No Google Firebase / Crashlytics
- ❌ No Facebook / Meta Graph SDK
- ❌ No Google AdMob / Unity Ads
- ❌ No Mixpanel / Amplitude
- ❌ No Cloud Relay / WebRTC third-party signaling

CastSprint relies 100% on Apple's standard built-in frameworks: `SwiftUI`, `Network.framework`, `VideoToolbox`, `CoreMedia`, `AVFoundation`, and `ReplayKit`.
