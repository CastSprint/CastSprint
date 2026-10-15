# CastSprint OBS Studio Integration Guide

## Overview
CastSprint is engineered specifically for mobile livestreaming and gameplay recording in OBS Studio. Unlike the macOS native AirPlay receiver (which hijacks the entire macOS desktop and lacks per-window capture/audio control), CastSprint provides a dedicated, clean, hardware-accelerated presentation window designed directly for OBS capture.

---

## 1. Video Setup in OBS Studio (Window Capture)

1. Launch **CastSprint** on macOS and connect your iPhone via USB.
2. Select your iPhone in CastSprint and click **START MIRRORING**.
3. (Optional) In CastSprint's Mirror View, click **"CLEAN OBS FEED"** in the top bar to hide all overlays and HUD counters.
4. Open **OBS Studio**.
5. In the **Sources** dock, click **+** and select **macOS Screen Capture**.
6. Set:
   - **Method:** `Window Capture`
   - **Window:** `[CastSprint] CastSprint`
   - **Show Cursor:** Checked or Unchecked (your preference).
7. Your iPhone gameplay now appears in OBS with zero latency, full 60 FPS, and perfectly preserved aspect ratio.

---

## 2. Audio Setup in OBS Studio

1. In OBS Studio, click **+** in Sources and add **macOS Audio Capture** (Application Audio Capture).
2. Select **CastSprint** as the target application.
3. Your mobile game audio streams cleanly into OBS as an isolated audio track, allowing separate mixing from your microphone, music, or alert sounds.
4. Zero feedback loops, zero desktop audio bleed.

---

## 3. Comparison with macOS System AirPlay Receiver

| Feature | CastSprint USB Direct | macOS System AirPlay |
| :--- | :--- | :--- |
| **OBS Window Capture** | Full Support (Dedicated Window) | **Impossible** (Hijacks entire screen) |
| **Isolated Audio in OBS** | Supported (Application Audio) | Mixed into System Master |
| **Latency** | Sub-15ms (Zero-copy USB) | 80–180ms (Wi-Fi AirPlay buffer) |
| **Wi-Fi Dependence** | None (Works offline with USB cable) | Requires Wi-Fi network |
| **Resolution & FPS** | Up to 1080p60 / 1440p60 | Variable / Compressed |
| **Mobile App Needed?** | **None** (Plug & Play via USB) | None |
