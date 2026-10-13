# Audio, Secure LAN & Recording Architecture

## 1. Secure Wireless Mirroring & Device Pairing

Screen mirroring carries private screen content (messages, game sessions, credentials). CastSprint enforces end-to-end security over local Wi-Fi without relying on any external cloud server or public certificate authorities.

### Security Guarantees
1. **Authenticated Encryption in Transit**:
   - Windows receiver hosts a TLS 1.2/1.3 listener using a desktop-generated self-signed X.509 certificate.
   - Client pins the desktop's SHA-256 certificate fingerprint during the TLS handshake (`TlsPinningSocketFactory`).
   - Zero "trust-all" fallbacks: any certificate mismatch immediately aborts the connection.
2. **Connection-Scoped Random Secrets**:
   - On launch, the receiver generates a random 6-digit session PIN (e.g. `123456`).
   - The PIN must be provided during the protocol `Hello` handshake.
   - Replay protection & unauthorized reconnection rejection: unknown tokens are instantly rejected with `HelloStatus::Rejected`.
3. **Local Network Restriction**:
   - Receiver binds only to local interfaces; no UPnP, no cloud relay, and no NAT hole punching.
4. **Local Network Discovery (mDNS)**:
   - Android client discovers desktop receivers advertising `_castsprint._tcp` via `NsdManager`.
   - TXT record carries `fp=<sha256>`, allowing one-tap pairing while prompting for the desktop PIN.
   - Manual host / port / PIN entry fallback is always available.

---

## 2. Android Game Audio Capture

### Android 10+ AudioPlaybackCapture
- Utilizes `AudioPlaybackCaptureConfiguration.Builder(mediaProjection)`:
  - `addMatchingUsage(AudioAttributes.USAGE_GAME)`
  - `addMatchingUsage(AudioAttributes.USAGE_MEDIA)`
  - `addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)`
- **Privacy & Permissions**:
  - Requires user-approved `MediaProjection` consent.
  - Zero microphone recording: microphone audio is never captured or accessed.
  - Respects Android system security policy: applications opting out via `android:allowAudioPlaybackCapture="false"` or `setAllowedCapturePolicy(ALLOW_CAPTURE_BY_NONE)` are protected and remain silent.
- **Encoding & Framing**:
  - `AudioRecord` configured for 48,000 Hz, 16-bit PCM, 2-channel stereo.
  - Real-time hardware/software encoding to AAC-LC using `MediaCodec` (`audio/mp4a-latm`).
  - Emits monotonic timestamps derived from `System.nanoTime() / 1000L` microsecond epoch, identical to the video encoder clock.

---

## 3. Windows Audio Playback

### Media Foundation AAC Decoder & WASAPI Shared-Mode
- **Media Foundation AAC MFT**:
  - Decodes incoming AAC-LC packets configured by `AudioConfig` into 16-bit 48kHz stereo PCM samples.
- **WASAPI Shared-Mode Client**:
  - Uses `IMMDeviceEnumerator` to acquire the default render endpoint (`eRender`, `eConsole`).
  - Event-driven buffer feeding (`AUDCLNT_STREAMFLAGS_EVENTCALLBACK`) into `IAudioRenderClient`.
  - MMCSS `Pro Audio` thread prioritization.
  - Integrated software volume and mute controls via `ISimpleAudioVolume`.
- **Audio Device Migration**:
  - Implements `IMMNotificationClient`. If default audio device changes or headphones are unplugged, automatically recovers and re-initializes the stream without desync or crash.

---

## 4. Audio/Video Synchronization

### Synchronizer Model (`AvSynchronizer`)
- Cross-device clock alignment:
  - Video and audio packets from Android share the same sender monotonic clock epoch.
  - Periodic `Heartbeat` messages track RTT ($t_1 - t_0$) and cross-device clock offset ($\Delta = t_{android} - (t_{win} + RTT / 2)$).
- **Presentation Scheduling**:
  - Audio playback is driven by the WASAPI audio clock.
  - Video frame PTS is evaluated against the current effective audio presentation timestamp:
    - **PresentNow**: Video frame is within synchronization window (e.g. within $[-15\text{ms}, +15\text{ms}]$).
    - **Wait**: Video frame is ahead of audio; scheduled for presentation at expected target time.
    - **DropLate**: Video frame is late beyond threshold (e.g. >25ms in Low Latency mode); dropped to prevent lag accumulation.
  - **User Audio Offset**:
    - User-configurable audio delay ($\pm 500$ ms in 10ms steps) to compensate for external display latency or Bluetooth headphones.

---

## 5. Gaming Stream Presets

| Preset | Target Resolution | Target FPS | Bitrate | Latency Buffering |
|---|---|---|---|---|
| **Low Latency** | 720p / 1080p | 60 FPS | 8 Mbps | ~10-25ms buffer, aggressive late-frame drop |
| **Balanced** | 1080p | 60 FPS | 12 Mbps | ~35-50ms buffer, smooth AV synchronization |
| **High Quality**| Native / 1440p / 4K | 60 FPS | 20 Mbps | ~70-120ms buffer, maximum visual fidelity |
| **Custom** | User selected | 30 / 60 FPS | 4 - 40 Mbps | Configurable |

---

## 6. Native Windows MP4 Local Recording

### Media Foundation Sink Writer (`Mp4Recorder`)
- Native container muxer (`MFCreateSinkWriterFromURL`).
- **Passthrough Multiplexing**:
  - Re-muxes incoming H.264 Annex-B NAL units directly into the MP4 container without re-encoding.
  - Re-muxes incoming AAC-LC audio frames directly into the MP4 container.
  - Zero transcoding overhead preserves gaming frame rates and CPU/GPU resources.
- **Clean Finalization**:
  - On stop, calls `IMFSinkWriter::Finalize()`, writing the `moov` atom and container metadata.
  - Resulting MP4 files are guaranteed valid and playable immediately in VLC, Windows Media Player, and OBS.
  - Supports video-only recording if game audio is disabled or protected.
