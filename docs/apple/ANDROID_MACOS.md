# CastSprint Android Mirroring on macOS

This document details the architecture, configuration, and operation of CastSprint Android mirroring (both over USB via ADB and over local Wi-Fi) on macOS.

---

## 1. Overview & Principles

CastSprint provides a completely native, low-latency gaming screen mirroring receiver on macOS that supports Android devices alongside iPhone/iPad.

### Key Principles
1. **100% Free Forever**: Zero paywalls, zero subscription prompts, zero ads, zero watermarks.
2. **Unified Architecture**: Shares the same CastSprint Protocol v1 (`CSP1`) wire format and protocol contracts used by CastSprint Windows.
3. **No Duplicate Codecs**: Uses native macOS hardware decoding (`VideoToolbox`) and GPU rendering (`Metal`) rather than heavy third-party software decoders.
4. **Official Tools**: Relies strictly on standard Android Platform Tools (`adb`) for reverse tunnel orchestration.
5. **Direct Local Communication**: Streams directly over USB cable or local subnet; zero cloud relays.

---

## 2. Android USB Transport (ADB Reverse)

Over USB, the Android CastSprint client runs as the capture producer and socket client, connecting to `127.0.0.1:27183`. The Mac runs the native `NetworkStreamReceiver` listening on TCP port `27183`.

### 2.1 ADB Reverse Forwarding Flow
```
+-----------------------------------------------------------------------------------------+
|                                    ANDROID DEVICE                                       |
|  [CastSprint Android App]                                                               |
|        |                                                                                |
|        v TCP connect("127.0.0.1:27183")                                                 |
|  [adbd daemon on phone]                                                                 |
+--------+--------------------------------------------------------------------------------+
         | (Physical USB Cable / USB Debugging)
         v
+--------+--------------------------------------------------------------------------------+
|  [adb server on Mac]                                                                    |
|        | adb reverse tcp:27183 tcp:27183                                                |
|        v                                                                                |
|  [CastSprint Mac NetworkStreamReceiver] (Port 27183, TCP_NODELAY)                       |
|        |                                                                                |
|        v                                                                                |
|  [VideoToolbox Hardware Decompressor] -> [MetalVideoRenderer] -> CAMetalLayer Display   |
+-----------------------------------------------------------------------------------------+
```

### 2.2 Orchestration in `ADBDeviceManager`
1. **Tool Discovery**: Probes standard candidate paths:
   - `/opt/homebrew/bin/adb`
   - `/usr/local/bin/adb`
   - `~/Library/Android/sdk/platform-tools/adb`
   - `/usr/bin/adb`
2. **Device Discovery**: Continuously runs `adb devices -l` on a background utility queue:
   - Parses device serial, state (`device`, `unauthorized`, `offline`), and model name.
   - Updates the unified device list displayed in `DashboardView`.
3. **Reverse Port Forwarding**:
   ```bash
   adb -s <serial> reverse tcp:27183 tcp:27183
   ```
4. **App Launch Automation**:
   ```bash
   adb -s <serial> shell am start -n com.castsprint.android/.MainActivity
   ```
5. **Clean Teardown**: Upon user disconnect or cable unplug, CastSprint releases the forward:
   ```bash
   adb -s <serial> reverse --remove tcp:27183
   ```

---

## 3. VideoToolbox Hardware Decoding Pipeline

Android `MediaCodec` encodes the device display into H.264 Annex-B formatted NAL units (`0x00000001` or `0x000001` start codes).

### 3.1 Parameter Set Ingestion (`VIDEO_CONFIG`)
When the Android encoder starts, it sends a `VIDEO_CONFIG` packet containing Annex-B SPS (NAL type 7) and PPS (NAL type 8) parameter sets:
1. `VideoToolboxDecoder` parses SPS and PPS NALUs out of the CSD payload, slicing away start codes.
2. Invokes `CMVideoFormatDescriptionCreateFromH264ParameterSets` to construct an active `CMVideoFormatDescription`.
3. Instantiates `VTDecompressionSession` configured for:
   - Pixel Format: `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (NV12).
   - Metal Compatibility: `kCVPixelBufferMetalCompatibilityKey: true`.
   - Realtime Mode: `kVTDecompressionPropertyKey_RealTime: true`.

### 3.2 Frame Decompression (`VIDEO_FRAME`)
1. Android sends compressed access units with monotonic microsecond timestamps (`pts_micros`) and keyframe flags.
2. `VideoToolboxDecoder` converts Annex-B start codes into 4-byte big-endian AVCC length headers.
3. Wraps the data in a `CMBlockBuffer` and `CMSampleBuffer`.
4. Dispatches the frame into `VTDecompressionSessionDecodeFrame`.
5. The hardware decompressor callback outputs a GPU-backed `CVPixelBuffer` directly to `MetalVideoRenderer` with zero CPU copy overhead.

---

## 4. Audio Playback Pipeline

1. Android captures system/game audio via `AudioRecord` / `AudioPlaybackCapture`.
2. Audio packets are delivered with monotonic presentation timestamps.
3. On macOS, `CoreAudioOutput` schedules the 48,000 Hz stereo PCM audio buffers with `AVAudioEngine` and `AVAudioPlayerNode`, delivering crystal-clear, low-latency game audio synchronized with the video stream.

---

## 5. User Instructions & Setup

### Requirements
- Mac running macOS 14.0 or later (Apple Silicon or Intel).
- Android phone running Android 10+ (API 29+) with Developer Options & USB Debugging enabled.
- Official Android Platform Tools (`brew install android-platform-tools`).

### Connecting Over USB
1. Connect the Android phone to the Mac with a USB cable.
2. Unlock the phone screen. If prompted with *"Allow USB debugging?"*, tap **Allow**.
3. Launch CastSprint on Mac.
4. Select the Android device in the device list.
5. Click **START MIRRORING**. CastSprint automatically establishes the reverse port proxy and initiates real-time mirroring!
