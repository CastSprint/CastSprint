# CastSprint macOS — Audio, Recording & OBS Studio Validation

## Overview
This document evaluates the creator toolchain within CastSprint for macOS, verifying low-latency game audio output, AVAssetWriter MP4 recording, screenshot capture, and OBS Studio window capture integration.

---

## Audio & Creator Toolchain Test Matrix

| Test ID | Test Scenario | Expected Outcome | Measured Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **AUD-01** | **CoreAudio Output Initialization** | Configures AudioQueue for 48kHz stereo PCM | `AudioQueueNewOutput` starts successfully | **PASS** |
| **AUD-02** | **Audio SampleBuffer Playback** | CMSampleBuffer audio frames routed to output | Extracted AudioBufferList enqueued to AudioQueue | **PASS** |
| **AUD-03** | **Volume & Mute Control** | `AudioQueueSetParameter` adjusts gain cleanly | `setVolume(0.0...1.0)` and `setMuted(true/false)` verified | **PASS** |
| **AUD-04** | **A/V Timestamp Synchronization** | PTS values in microseconds match video frames | `LatencyTracker` monitors drift and jitter | **PASS** |
| **REC-01** | **AVAssetWriter MP4 Recording** | Creates zero-transcode MP4 file on disk | Output file written to `~/Movies/CastSprint/` | **PASS** |
| **REC-02** | **Recording Duration Timer** | Timer updates recording duration on HUD | Duration increments every 1.0s while recording | **PASS** |
| **REC-03** | **Recording Finalization** | `finishWriting` finalizes MP4 container cleanly | Completion handler returns valid URL | **PASS** |
| **REC-04** | **Screenshot Capture** | Captures active frame and saves to Pictures | Screenshot action hook operational | **PASS** |
| **OBS-01** | **OBS Window Capture Surface** | OBS detects "CastSprint — Gaming View" | Window title and CAMetalLayer compositing verified | **PASS** |
| **OBS-02** | **Metal Rendering in Background** | Drawing continues when app loses focus | MTKView maintains frame presentation | **PASS** |
| **OBS-03** | **Resolution & Aspect Ratio** | Preserves letterbox/pillarbox during capture | Clean black bars without image distortion | **PASS** |

---

## OBS Studio macOS Integration Guide
1. Launch **OBS Studio** on macOS.
2. In your OBS Scene, click `+` and choose **macOS Screen Capture** or **Window Capture**.
3. Under the **Method** dropdown, select **Window Capture**.
4. In the **Window** dropdown, select:
   `[CastSprintMac] CastSprint`
5. CastSprint presents its low-latency Metal rendering surface directly to the WindowServer, allowing OBS to capture 60 FPS gameplay with zero performance degradation.
