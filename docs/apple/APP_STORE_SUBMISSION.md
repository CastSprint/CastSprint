# CastSprint for iOS — App Store Submission Package & Review Guide

**Target App Store:** iOS & iPadOS App Store  
**Application Name:** CastSprint — Gaming Screen Mirror  
**Bundle Identifier:** `com.castsprint.ios`  
**Broadcast Extension Bundle Identifier:** `com.castsprint.ios.broadcast`  
**App Group Identifier:** `group.com.castsprint.ios`  
**Deployment Target:** iOS 15.0+ / iPadOS 15.0+  
**Release Pricing:** 100% Free ($0.00) · No In-App Purchases · No Subscriptions · No Ads  

---

## 1. App Store Connect Product Page Metadata

### App Information
* **Primary Language:** English (U.S.)
* **App Name:** CastSprint — Gaming Screen Mirror
* **Subtitle (30 characters max):** Low-Latency Screen & Audio (28 chars)
* **Primary Category:** Utilities
* **Secondary Category:** Entertainment / Games
* **Content Rights:** Yes, contains original content owned by the developer.
* **Age Rating:** 4+ (No violence, no mature content, no user-generated content).

### Promotional Text (170 characters max)
> Stream iPhone & iPad gameplay directly to your Windows PC or Mac over local Wi-Fi with synchronized game audio. 100% free, no watermarks, no cloud relay. (152 chars)

### Description
```
CastSprint is a high-performance, native iOS screen mirroring application engineered specifically for mobile gamers, livestreamers, and content creators. Stream your iPhone or iPad display directly to your Windows PC or Mac with ultra-low latency and crystal-clear game audio.

WHY MOBILE GAMERS CHOOSE CASTSPRINT:
• Ultra-Low Latency: Hardware-accelerated VideoToolbox H.264 video encoding ensures real-time responsiveness for fast-paced competitive games (PUBG Mobile, Call of Duty: Warzone, Genshin Impact, Wild Rift).
• Synchronized Game Audio: Native game sound effects and background music are streamed directly to your desktop receiver with precise sub-frame synchronization.
• Up to 60 FPS Smooth Mirroring: Support for 720p 60 FPS, 1080p 60 FPS, and Native Retina resolutions.
• Direct Local Network Streaming: 100% direct peer-to-peer Wi-Fi connection over your local network using Apple Network.framework. Video never leaves your home network and never touches an external cloud server.
• Driverless USB Mirroring on Mac: Connect your iPhone to your Mac via USB-C or Lightning cable for instant zero-latency mirroring with no mobile app required!
• Instant Pairing: Automatic Bonjour local network discovery, manual IP entry, and quick QR code scanning.
• Optional Voice Commentary: Toggle microphone input to add live commentary to your desktop gameplay stream.
• OBS Studio Ready: Mirror your mobile gameplay directly into CastSprint Desktop on Windows or macOS for seamless OBS game capture, livestreaming, and Discord screen sharing.

THE CASTSPRINT PRIVACY & FREEDOM PROMISE:
• 100% Free Forever: No hidden fees, no subscriptions, and no trial periods.
• No Account Required: Launch the app and start mirroring immediately. No registration, email, or login.
• No Watermarks: Your stream is clean and unbranded.
• No Mandatory Advertisements: Enjoy a pure gaming experience without interruptions.
• No Cloud Relay: Video and audio travel strictly between your iPhone and your computer over your local subnet.
• Zero Remote Analytics: We do not track, collect, or upload your usage data or personal information.
```

### Keywords (100 characters max)
```
screen mirror,gaming mirror,stream gameplay,iphone to pc,obs capture,replaykit,low latency,wifi stream
```

### URLs
* **Support URL:** https://github.com/CastSprint/CastSprint/issues
* **Marketing URL:** https://github.com/CastSprint/CastSprint
* **Privacy Policy URL:** https://github.com/CastSprint/CastSprint/blob/main/docs/PRIVACY.md

---

## 2. App Privacy Questionnaire (Nutrition Label)

When configuring **App Privacy** in App Store Connect:

| Question | Selection | Justification / Notes |
|:---|:---:|:---|
| **Do you or your third-party partners collect data from this app?** | **NO** | Select **"Data Not Collected"**. CastSprint contains zero analytics, tracking, advertising, or crash reporting SDKs. |
| **Tracking Purposes** | **NO** | App does not track users across other companies' apps or websites. |
| **User Identification** | **NO** | No accounts, logins, or personal identifiers are collected. |

---

## 3. Screenshots Checklist & Creative Guidelines

Prepare screenshots adhering to Apple's specifications:

### Required Display Sizes:
1. **6.9" Display (iPhone 16 Pro Max / 15 Pro Max):** `1320 × 2868` or `1290 × 2796` pixels.
2. **6.7" Display (iPhone 14 Pro Max / 13 Pro Max):** `1284 × 2778` pixels.
3. **13" iPad Pro Display (M4 / M2):** `2064 × 2752` pixels.
4. **11" iPad Pro Display:** `1668 × 2388` pixels.

### Planned Screenshots:
* **Screenshot 1 (Hero / Brand):** CastSprint Home Screen showing "Discovered Computers" list with PC and Mac receiver cards and active green status pill. Headline: *"Stream Mobile Gameplay at 60 FPS"*.
* **Screenshot 2 (Quality Presets):** Stream Settings screen showing Low Latency (720p60), Balanced (1080p60), and High Quality (Native 60fps) options with Game Audio toggled ON. Headline: *"Ultra-Low Latency Hardware Encoding"*.
* **Screenshot 3 (Pairing):** QR Code Scanner interface pointing at a desktop monitor with successful haptic pairing prompt. Headline: *"Instant Local Pairing in Seconds"*.
* **Screenshot 4 (Active Session HUD):** Active Session HUD displaying live throughput (12.4 Mbps), 60 FPS lock, streaming timer, and connected PC name. Headline: *"Real-Time Performance Dashboard"*.
* **Screenshot 5 (Desktop & OBS Ready):** Side-by-side visualization of iPhone running a game and CastSprint Desktop running on PC/Mac with OBS Studio capturing clean video. Headline: *"100% Free · No Watermarks · OBS Studio Ready"*.

---

## 4. App Store Reviewer Notes (App Review Information)

Include the following instructions in the **App Review Information** section to ensure smooth approval:

```
NOTE TO APP STORE REVIEW TEAM:

CastSprint is an open-source local network screen mirroring tool designed for mobile gamers to mirror their iPhone/iPad display to their own Windows PC or Mac.

HOW TO TEST CASTSPRINT:
1. To test real-time mirroring, download and launch the free, open-source CastSprint Desktop receiver on a Windows PC or Mac connected to the same Wi-Fi network as the test iOS device:
   - Mac Receiver: https://github.com/CastSprint/CastSprint/releases
   - Windows Receiver: https://github.com/CastSprint/CastSprint/releases
2. Launch CastSprint on the iOS device.
3. The app uses standard Apple Bonjour (_castsprint._tcp) over the local Wi-Fi subnet to automatically discover the running computer receiver. Alternatively, you can enter the local IP address manually.
4. Tap "Launch Broadcast Picker". Apple's system ReplayKit modal will appear with "CastSprint" selected.
5. Tap "Start Broadcast". After Apple's standard 3-second countdown, the screen and game audio will mirror smoothly to your desktop receiver.

COMPLIANCE & PERMISSIONS JUSTIFICATION:
- Screen Capture: Implemented exclusively via public, documented ReplayKit (RPBroadcastSampleHandler) and system RPSystemBroadcastPickerView. Capture is initiated solely with explicit user consent.
- Local Network (NSLocalNetworkUsageDescription): Required to discover and transmit video frames directly to the desktop receiver over the local LAN (TCP port 27183). Video never leaves the home network and never touches any remote server.
- Camera (NSCameraUsageDescription): Used solely to scan the pairing QR code displayed by the desktop receiver. Camera frames are processed entirely in-memory and are never stored or transmitted.
- Microphone (NSMicrophoneUsageDescription): Commentary microphone audio is disabled by default and is only captured if the user explicitly enables the voice commentary toggle. Game audio works without microphone permissions.
- Zero In-App Purchases / Subscriptions: CastSprint is completely free with no paywalls or user accounts.

If you have any questions or require a pre-configured local test setup, please contact:
support@castsprint.com / github.com/CastSprint/CastSprint
```

---

## 5. TestFlight External Beta Plan

* **Target Beta Group:** 50–100 mobile gamers, streamers, and open-source contributors.
* **Test Focus Areas:**
  1. Wi-Fi discovery speed across varied router topologies (5 GHz, Wi-Fi 6, mesh routers).
  2. Sub-50ms latency stability during intensive 60 FPS gameplay (Genshin Impact, Wild Rift).
  3. Audio-video synchronization under varied network conditions.
  4. Memory budget compliance: verifying ReplayKit extension remains strictly under 25 MB (<50 MB system limit).
  5. Recovery behavior on incoming calls, lock screen, and background transitions.
