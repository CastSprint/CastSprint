# Real-Device Test: OBS Studio Gameplay Capture & Audio Verification

## 1. Test Overview & Objectives
Validate that OBS Studio captures the CastSprint native gameplay surface and digital game audio cleanly for livestreaming (YouTube, Twitch, Facebook Gaming).

---

## 2. Test Configuration & Setup
- **Desktop Application**: `/Applications/CastSprint.app`
- **Livestream Software**: OBS Studio
- **Video Source**: macOS Screen Capture ➔ Window Capture ➔ `[CastSprint] CastSprint`
- **Audio Source**: Audio Input Capture ➔ `iPhone` (via IDAM) or macOS Application Audio Capture

---

## 3. Observed Results & Verification Criteria

| Verification Metric | Requirement | Observed Result | Status |
| :--- | :--- | :--- | :--- |
| **Window Selection in OBS** | Stable window title | Easily selectable in OBS Window Capture dropdown | **PASS** |
| **Clean Video Surface** | Zero UI overlays in stream | `CLEAN OBS FEED` toggles off top HUD overlays | **PASS** |
| **Aspect Ratio Preservation** | Correct letterboxing | Maintained on 16:9, 19.5:9, and 20:9 devices | **PASS** |
| **Orientation Changes** | Smooth rotation | Adapts instantly between portrait and landscape | **PASS** |
| **Internal Game Sound** | Audible in recording | Game music, footsteps, gunshots clearly captured | **PASS** |
| **Microphone Isolation** | Zero room mic noise | Pure digital audio; room noise completely isolated | **PASS** |
| **A/V Sync Accuracy** | Synchronized audio | Audio and video in sync throughout long sessions | **PASS** |
| **Recorded Clip Inspection** | Playable MP4 file | Non-black frames, smooth 60 FPS motion | **PASS** |
