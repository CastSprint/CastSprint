# Google Play Store Listing Draft

## Application Title
**CastSprint — Gaming Screen Mirror**

## Short Description (max 80 chars)
Free low-latency Android-to-PC screen and game audio mirroring for streamers.

## Full Description
CastSprint is a professional, free screen mirroring application engineered for mobile gamers, content creators, and livestreamers. Mirror your mobile gameplay directly to your Windows PC with ultra-low latency, crisp 60 FPS visuals, and high-fidelity internal game audio — with zero watermarks, zero subscriptions, and zero advertisements.

### ⚡ FEATURES FOR MOBILE GAMERS
- **Ultra-Low Latency**: Native hardware-accelerated H.264 pipeline (~15ms USB latency, <75ms total screen-to-display latency).
- **Internal Game Audio (Android 10+)**: Streams crystal-clear 48kHz stereo game audio directly to Windows via WASAPI.
- **Lock 60 FPS Gaming**: Optimized for high-speed action, Battle Royale, MOBA, and racing titles.
- **Native USB & Secure Wi-Fi**: Connect via standard USB cable with ADB reverse or enjoy wireless LAN streaming protected by TLS certificate pinning.
- **OBS Studio Ready**: Designed specifically for easy window capture in OBS Studio without black borders, watermarks, or overlays.
- **Gaming Stream Presets**:
  - *Low Latency*: 720p/1080p 60fps for competitive shooters.
  - *Balanced*: 1080p 60fps with smooth AV sync for RPGs and casual games.
  - *High Quality*: 2K/4K/Native resolution for video review and tablet displays.
  - *Custom*: Fine-tune your resolution, target FPS, and bitrate up to 40 Mbps.
- **Smart Thermal Management**: Automatically manages bitrate during extended gaming sessions to protect your device from overheating.

### 🔒 PRIVACY FIRST & 100% FREE
- **Free Forever**: No pro tiers, no locked resolutions, no trial periods, no watermarks.
- **Zero Ads**: No banner ads, no popups, no video interruptions during your gameplay.
- **No Cloud Relays**: Your screen content never leaves your physical local network.
- **No Accounts Required**: No email, no registration, no tracking.

### 📋 PERMISSIONS & PRIVACY DISCLOSURE
- **Screen Capture (MediaProjection)**: Used exclusively to mirror your display while the foreground service is active.
- **Record Audio**: Used solely with Android's native `AudioPlaybackCapture` to capture game and media audio. Microphone audio is never accessed.
- **Local Network**: Used strictly for local Wi-Fi pairing and mDNS discovery on your private home network.
