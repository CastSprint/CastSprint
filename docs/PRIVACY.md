# CastSprint Privacy Policy & Free Forever Commitment

CastSprint is committed to absolute user privacy, zero data collection, and open native systems engineering.

---

## 1. Core Privacy Architecture

### No Cloud Servers
CastSprint does not operate any cloud servers, databases, relays, or web services. All video and audio streams flow directly point-to-point between your Android device and your Windows PC over a local physical USB cable or your private home Wi-Fi network.

### No Accounts or Personal Information
- No sign-up, email, phone number, or login required.
- No device identifiers or tracking identifiers (IMEI, MAC address, advertising IDs) are ever collected, transmitted, or logged.
- No crash analytics, remote telemetry SDKs, or third-party trackers are bundled.

### Local-Only Network Transmission
- **USB Mode**: Transmits over an isolated local loopback socket via ADB (`127.0.0.1`).
- **Wi-Fi Mode**: Transmits over local LAN sockets encrypted with TLS and pinned with a SHA-256 certificate fingerprint. Traffic never leaves your local Wi-Fi network and is never exposed to the public Internet.

---

## 2. Android App Permission Disclosures

CastSprint requests only the minimal set of documented Android permissions required for screen mirroring and game audio capture:

| Permission | Purpose | Why It Is Safe |
|---|---|---|
| `FOREGROUND_SERVICE_MEDIA_PROJECTION` | Captures your screen content after explicit consent. | Active only while mirroring. Displays an ongoing system notification with an instant **Stop** button. |
| `RECORD_AUDIO` | Captures internal game and media audio via `AudioPlaybackCapture`. | Used exclusively with `AudioPlaybackCaptureConfiguration`. **The microphone is never opened or recorded.** Apps that disallow audio capture remain completely silent. |
| `INTERNET` | Enables local TCP socket communication to the PC receiver. | Connects only to local IP addresses (`127.0.0.1` or LAN subnet). No remote server connections. |
| `ACCESS_NETWORK_STATE` & `ACCESS_WIFI_STATE` | Detects whether the device is on Wi-Fi and retrieves the local subnet. | Used solely for local network discovery. |
| `CHANGE_WIFI_MULTICAST_STATE` | Discovers PC receivers via mDNS (`_castsprint._tcp`). | Required by Android `NsdManager` to listen for local service advertisements. |
| `POST_NOTIFICATIONS` (Android 13+) | Displays the required foreground service notification. | Informs you whenever screen capture is actively running. |

---

## 3. Free Forever Policy

CastSprint is free forever. To preserve the integrity of gaming and livestreaming, we pledge:
- **No Paywalls**: Every resolution (720p, 1080p, 2K, 4K, Native) and frame rate (30 FPS, 60 FPS) is 100% free.
- **No Subscriptions**: There are no premium tiers, pro licenses, or paid unlocks.
- **No Advertisements**: Zero banner ads, interstitial ads, or compulsory video ads.
- **No Watermarks**: Your gameplay and local MP4 recordings will never be branded with a CastSprint logo or watermark. Your content belongs to you.
- **Voluntary Contributions**: Development is supported entirely through voluntary community sponsorship and open-source contributions. Donations are never required to access any feature.

---

## 4. Local Recordings

When you record gameplay on Windows using CastSprint's MP4 recorder, the files are written directly to your chosen local disk folder (default: `Videos\CastSprint`). CastSprint does not upload, inspect, or manage your recordings.
