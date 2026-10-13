# OBS Studio Livestreaming & Recording Guide (macOS)

CastSprint for macOS is built specifically for esports livestreaming and content creation with **OBS Studio**. By presenting video frames through a hardware `CAMetalLayer` and native AppKit window, OBS can capture mobile gameplay with zero latency and zero frame tearing.

---

## 1. Quick Setup in OBS Studio

```
+-------------------------------------------------------------+
|  Physical iPhone (Running Mobile Game)                      |
+------------------------------+------------------------------+
                               | USB Lightning / USB-C
                               v
+-------------------------------------------------------------+
|  CastSprint for macOS                                       |
|  - Window Title: "CastSprint — Gaming View"                 |
|  - Metal Video Surface (CAMetalLayer)                       |
+------------------------------+------------------------------+
                               | macOS ScreenCaptureKit
                               v
+-------------------------------------------------------------+
|  OBS Studio for macOS                                       |
|  - Source 1: Window Capture (Metal Surface)                 |
|  - Source 2: macOS Application Audio Capture (Game Audio)   |
+-------------------------------------------------------------+
```

### Video Capture Step-by-Step
1. Launch **CastSprint for Mac** and start mirroring your USB-connected iPhone.
2. In **OBS Studio for macOS**, go to your desired Scene and click **`+`** under the **Sources** dock.
3. Select **Window Capture** (or **macOS ScreenCaptureKit Window Capture** in OBS 29+).
4. Name the source (e.g., `iPhone Screen Mirror`).
5. In the Window dropdown, select:
   ```
   [CastSprint]: CastSprint — Gaming View
   ```
6. Set **Capture Method** to **Automatic** or **ScreenCaptureKit**.
7. Ensure **Show Cursor** is toggled off for clean gameplay viewing.

---

## 2. Audio Capture Configuration

CastSprint routes game audio directly through CoreAudio. In OBS Studio on macOS, you have two flexible methods to route game audio into your stream:

### Method A: Application Audio Capture (Recommended)
*Available natively in OBS Studio 29+ on macOS 13+.*
1. In OBS, click **`+`** under **Sources** and choose **macOS Application Audio Capture (BETA)**.
2. Name the source `Mobile Game Audio`.
3. In the Application dropdown, select **CastSprint**.
4. **Benefit**: Mobile game audio is completely isolated from Discord, Spotify, and browser notifications.

### Method B: Virtual Audio Cable (BlackHole)
1. Install [BlackHole 2ch](https://existential.audio/blackhole/) (Free open-source virtual audio driver).
2. Set CastSprint audio output or macOS system output to BlackHole.
3. In OBS, add an **Audio Input Capture** source targeting BlackHole 2ch.

---

## 3. Aspect Ratio & Display Orientation

Mobile games dynamically alternate between **Landscape** (16:9, 19.5:9, 20:9) and **Portrait** (9:16).

- **Zero Distortion**: CastSprint's Metal renderer automatically letterboxes or pillarboxes the frame inside the window. Gameplay geometry is never stretched or distorted.
- **Window Resizing**: When you resize the CastSprint window on Mac, OBS Window Capture dynamically scales the source within your OBS canvas.
- **Orientation Lock**: For competitive games (PUBG Mobile, Call of Duty: Mobile, Genshin Impact), lock the device in landscape mode before starting the match.

---

## 4. Low-Latency Encoder Settings for Streaming

To preserve the sub-20ms responsiveness of CastSprint when broadcasting to Twitch, YouTube, or Kick:

| Setting | Recommended Value | Rationale |
|:---|:---:|:---|
| **Video Encoder** | Apple VT H.264 Hardware Encoder | Apple Silicon hardware compression |
| **Rate Control** | CBR | Predictable bandwidth |
| **Bitrate** | 6,000 – 8,000 kbps | Crisp 1080p 60 FPS motion |
| **Keyframe Interval** | 2 seconds | Streaming platform requirement |
| **Profile** | High | Maximum compression efficiency |

---

## 5. Troubleshooting OBS on macOS

### Symptom: Window Capture shows a black box
- **Solution**: Ensure macOS **Screen Recording permission** is granted to OBS Studio (`System Settings` → `Privacy & Security` → `Screen Recording` → enable `OBS`).
- In OBS Window Capture properties, toggle between "ScreenCaptureKit" and "Window Capture".

### Symptom: Frame stutter during intensive PC gaming
- **Solution**: Set CastSprint Quality Profile to **Performance (720p 60fps)** or **Balanced (1080p 60fps)** in `Settings`. This reduces GPU load on MacBook Air and baseline M1 Macs.
