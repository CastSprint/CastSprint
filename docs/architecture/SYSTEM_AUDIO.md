# CastSprint — System & Game Audio Architecture

## 1. Zero Microphone Noise Guarantee
CastSprint has a non-negotiable rule regarding audio:
**Never capture physical room microphones and label them as game audio.**
Ambient room noise, keyboard clicks, breathing, and chair creaks must never pollute the mobile game audio stream.

---

## 2. Audio Capture Architecture by Platform

### 2.1 iPhone over USB on macOS (Inter-Device Audio Mode - IDAM)
- **Mechanism**: Apple's native CoreAudio IDAM subsystem.
- **Activation**:
  When an iPhone is connected via USB, opening `Audio MIDI Setup.app` exposes the device with an "Enable" button. Once enabled, macOS registers the iPhone as an aggregate digital input device:
  - Channels: 2 (Stereo)
  - Sample Rate: 48,000 Hz (48 kHz)
  - Format: 32-bit floating point or 24-bit integer
  - Source: 100% digital internal audio bus (games, music, apps).
- **OBS Routing**:
  In OBS Studio: Add `Audio Input Capture` ➔ Select `iPhone`.
  This provides pristine game sound directly into the stream mixer with 0% microphone noise.

### 2.2 iPhone over Wi-Fi (ReplayKit Broadcast Extension)
- **Mechanism**: `LegacyBroadcastExtension/SampleHandler.swift`.
- **Buffer Type**: Handles `CMSampleBuffer` of type `RPSampleBufferType.audioApp`.
- **Encoding**: 48kHz 16-bit linear PCM or AAC encoded via `AudioToolbox`.
- **Packet Structure**: Framed as CastSprint Protocol V1 `AudioFrame` packets with presentation timestamps (PTS).

### 2.3 Android over USB & Wi-Fi (AudioPlaybackCapture API)
- **Mechanism**: Android 10+ (API level 29+) `AudioPlaybackCaptureConfiguration`.
- **Target Usages**:
  - `AudioAttributes.USAGE_GAME`
  - `AudioAttributes.USAGE_MEDIA`
- **Capture Interface**: `AudioRecord` configured with the playback capture configuration.
- **Handling Protected Audio**:
  If a third-party app sets `ALLOW_CAPTURE_BY_NONE`, Android blocks playback capture. In this scenario, CastSprint honestly reports that audio capture is restricted by the source application rather than falling back to the room microphone.
