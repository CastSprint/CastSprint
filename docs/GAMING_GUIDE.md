# CastSprint — The Ultimate Mobile Gaming & Streaming Guide
### Zero-Latency Mirroring, Zero-Delay Audio & Thermal Cooling for PUBG Mobile, BGMI, Free Fire & COD Mobile

---

## 1. Why CastSprint is the #1 Choice for Mobile Gamers

Most mobile gamers streaming to YouTube, Facebook, Twitch, or Kick use either an expensive hardware capture card ($150–$250 Elgato) or software like DouWan. However, software alternatives like DouWan suffer from major flaws:
1. **Aggressive Watermarks & Paywalls**: Free versions plaster ugly watermarks over your game and cap recordings at 2 minutes to force a $10–$20/year VIP subscription.
2. **Audio Delay (Footstep Desync)**: Competitors typically have a 200ms–300ms sound delay. In fast-paced tactical shooters (PUBG, Free Fire), missing an enemy footstep or hearing a gunshot late gets you eliminated.
3. **Phone Overheating (Thermal Throttling)**: Running intense 3D games while keeping the mobile OLED display at maximum brightness causes phones to boil, leading to severe FPS drops (e.g. from 90 FPS down to 35 FPS) after 15 minutes of streaming.
4. **Bloatware & Dual-GPU Lag**: Electron or .NET-based tools consume 400MB+ RAM and trigger stutter on dual-GPU laptops (Intel + NVIDIA).

**CastSprint solves every single one of these problems:**
* **100% Free Forever**: Zero watermarks, zero subscriptions, zero ads, zero accounts.
* **Pure Rust Core & Native Viewport**: Binary size is only **693 KB**, RAM usage is **<30 MB**, and startup time is **0.1 seconds**.
* **Hardware AV Synchronizer**: Monotonic clock regression with $\alpha=0.1$ drift smoothing ensures bit-perfect lip-sync and instant audio cues (footsteps arrive with zero audible delay).
* **Thermal Cooling Mode (`C` Hotkey)**: Instantly dims the phone screen to near-zero brightness to eliminate phone overheating while the PC monitor runs at 100% full brightness and maximum FPS.
* **Streamer Clean Capture Mode (`H` Hotkey)**: One-click toggle hides the HUD overlay for a 100% clean tournament broadcast feed in OBS Studio.

---

## 2. Ultra-Low-Latency USB Setup (Recommended for Tournaments)

Wired USB mirroring is the competitive gold standard, offering sub-25ms latency with zero Wi-Fi packet drops.

### Step 1: Prepare Your Mobile Device
* **Android (Samsung, Xiaomi, OnePlus, Pixel, ROG Phone)**:
  1. Go to **Settings > About Phone** and tap **Build Number** 7 times to unlock Developer Options.
  2. In **Developer Options**, enable **USB Debugging**.
  3. Connect your phone to your PC via a high-speed USB-C cable (USB 3.0/3.2 recommended).
  4. Allow the *"Allow USB debugging?"* prompt on your phone display.
* **iPhone / iPad**:
  1. Connect your iPhone/iPad to your PC or Mac with a Lightning/USB-C cable.
  2. Tap **Trust This Computer** and enter your passcode.

### Step 2: Launch CastSprint Desktop Receiver
On your Windows PC or Linux rig, run:
```bash
castsprint-desktop
```
*(Or launch `CastSprintMac` on Apple macOS).*

CastSprint automatically discovers connected Android devices via ADB, sets up the reverse tunnel (`adb reverse tcp:27183 tcp:27183`), and pops up the native dark gaming viewport window!

### Step 3: Connect and Play
* Open **CastSprint** on your phone -> Select **USB Mode** -> Tap **Start Mirroring**.
* Your phone's screen and internal game sound immediately appear in the desktop viewport!

---

## 3. Thermal Cooling Mode — Stop Phone Overheating & FPS Drops

### The Problem:
Mobile processors (Snapdragon 8 Gen 2/3, Dimensity 9300, Apple A16/A17) generate massive heat when running 90/120 FPS games. When the phone display is also on at high brightness, the battery temperature easily exceeds 45°C, triggering thermal throttling that ruins your gameplay.

### The Solution:
Press **`C`** on your keyboard at any time while mirroring (or launch with `--cooling`):
1. CastSprint instantly sends a hardware command dimming the phone screen to minimum brightness (value: 1).
2. The phone's GPU and CPU remain running at 100% full speed, delivering pristine 60/90/120 FPS video frames over the USB cable.
3. Your phone stays cool to the touch, battery consumption drops by up to 60%, and thermal throttling is completely prevented!
4. When you finish your gaming session, press **`C`** again to restore normal screen brightness.

---

## 4. Professional OBS Studio Livestreaming Setup

CastSprint is engineered specifically for clean OBS Studio streaming without needing window cropping or capture card dongles.

```
+------------------------------------+
| Mobile Phone (Game + Audio)        |
+------------------------------------+
                  |
         High-Speed USB Cable
                  |
                  v
+------------------------------------+
| CastSprint Native Rust Desktop     |  <--- Press 'H' for Clean Mode
| Receiver (Port: 27183)             |  <--- Press 'C' for Cooling Mode
+------------------------------------+
       |                     |
  Window Capture        Game Audio
  (DirectX/Wayland)    (WASAPI/PipeWire)
       |                     |
       +----------+----------+
                  |
                  v
       +--------------------+
       | OBS Studio         |
       | 1080p60 Tournament |
       | Broadcast Feed     |
       +--------------------+
```

### 1. Adding Video to OBS Studio:
1. Open **OBS Studio** -> In the **Sources** dock, click **`+`** -> Select **Window Capture**.
2. Name it `CastSprint Mobile Game`.
3. In properties:
   * **Window**: Select `[castsprint-desktop]: CastSprint Studio Viewport`.
   * **Capture Method**: Select **`Windows 10 (1903 and up)`** (on Windows) or **`PipeWire / ScreenCaptureKit`** (on Linux/Mac).
4. In the CastSprint viewport, press **`H`** on your keyboard to hide the top/bottom HUD bars. OBS now captures a 100% clean, borderless mobile game feed!

### 2. Capturing Isolated 48kHz Game Audio:
1. In OBS, click **`+`** under **Sources** -> Select **Application Audio Capture (BETA)**.
2. Select `castsprint-desktop` from the application list.
3. Game audio (footsteps, gunshots, vehicles) now flows directly into your stream without capturing your Discord chat, Spotify music, or Windows notification sounds!

### 3. Alternative: Direct OBS / FFmpeg Pipeline (`--stdout-pipe`)
For advanced broadcasting setups, stream raw Annex-B frames directly without rendering a desktop window:
```bash
# Pipe directly into ffplay or virtual camera loopback
castsprint-desktop --stdout-pipe | ffplay -fflags nobuffer -flags low_delay -i -
```

---

## 5. Complete Keyboard Hotkeys Reference

| Key | Feature | Action |
|:---:|---|---|
| **`F11`** | **Borderless Fullscreen** | Expands the viewport to fill your entire PC monitor without window borders. |
| **`H`** | **Toggle HUD Overlay** | Hides/shows the telemetry bar. Keep hidden during OBS streaming. |
| **`C`** | **Thermal Cooling Mode** | Dims phone display to prevent overheating and battery drain. |
| **`S`** | **Instant Screenshot** | Saves uncompressed 32-bit BMP snapshot to `~/Pictures/CastSprint`. |
| **`R`** | **Lossless Recording** | Starts/stops writing raw H.264 Annex-B frames directly to disk. |
| **`1`** | **Ultra Low-Latency** | AV sync preset tuned for competitive 10ms shooter reactions. |
| **`2`** | **Balanced Gaming** | Standard 25ms AV sync smoothing for RPGs, MOBAs, and racing. |
| **`3`** | **High-Quality Cinematic** | 50ms buffer smoothing for high-bitrate video and movies. |
| **`Esc`** | **Exit Fullscreen** | Restores normal windowed mode from fullscreen. |
| **Mouse Click** | **Touch Tap Forwarding**| Click anywhere in the viewport to tap that exact point on your phone. |

---

## 6. Pro-Gamer Optimal Settings for Popular Games

### PUBG Mobile / BGMI:
* **Graphics**: Smooth + 90 FPS (or Extreme+ 120 FPS if device supports).
* **Audio**: Ultra High.
* **CastSprint Sync Preset**: Press **`1`** (Ultra Low-Latency).
* **Cooling Mode**: Press **`C`** as soon as you enter the spawn island.

### Free Fire / Free Fire MAX:
* **Graphics**: Max + High FPS (Normal shadow).
* **CastSprint Mode**: Physical USB.
* **Cooling Mode**: Press **`C`** to maintain constant 60 FPS without frame drops.

### Call of Duty Mobile (CODM):
* **Graphics**: Low / Medium (for maximum 120 FPS consistency).
* **Audio**: High Quality stereo.
* **CastSprint Mode**: Physical USB + Fullscreen (`F11`).

---

## 7. Troubleshooting Common Issues

* **Laggy video or micro-stutters?**
  * Ensure you are using a USB 3.0 port (blue port) on your PC motherboard, not an unpowered USB hub.
  * In the mobile app settings, set encoder bitrate to 16–25 Mbps.
* **Game sound plays out of phone instead of PC?**
  * Android requires Android 10 or newer for internal audio capture (`AudioPlaybackCapture`). Ensure you granted the audio permission when starting mirroring.
* **Window Capture in OBS is black?**
  * In OBS Window Capture properties, change Capture Method to **Windows 10 (1903 and up)**.
