# CastSprint macOS Wireless (LAN) Mirroring Architecture

This document specifies the wireless local network (LAN) screen mirroring architecture for CastSprint on macOS, supporting both Android clients and native iOS senders.

---

## 1. Security & Privacy Guarantees

1. **Zero Cloud Relay**: Streaming remains 100% confined to the local Wi-Fi subnet. No audio, video, or telemetry ever leaves your private network.
2. **Local Pairing PIN**: Connections require mutual user approval via a dynamic 4-digit pairing PIN published in mDNS TXT records and verified on initial handshake.
3. **Replay & Session Protection**: Every session is assigned a cryptographically random 32-bit session ID. Packets outside the active session or with mismatched sequence windows are dropped.
4. **No Default WAN Listening**: Network receiver binds strictly to local network interfaces (`local.` domain); no public routing.

---

## 2. mDNS Bonjour Service Advertisement

CastSprint Mac announces its presence on the local network using Apple's Bonjour (`NetService`) subsystem.

### Service Definition
- **Domain**: `local.`
- **Service Type**: `_castsprint._tcp.`
- **Port**: `27183` (Default `CSP_DEFAULT_PORT`)
- **Service Name**: `CastSprint Mac (<HostName>)`

### TXT Record Payload
| Key | Type | Description |
|:---|:---|:---|
| `version` | String | Protocol version string (e.g. `1.0`) |
| `pin` | String | Active 4-digit pairing PIN (e.g. `4829`) |
| `platform` | String | Receiver operating system (`macOS`) |

Mobile devices scanning the local subnet detect the Mac immediately, resolve its IP and port, and present it in their connection pickers.

---

## 3. Network Transport & Stream State Machine

CastSprint uses `Network.framework` (`NWListener` and `NWConnection`) with low-latency TCP tuning.

```
       Mobile Client                                     Mac Receiver
             |                                                 |
             |-------- (TCP Connect Port 27183) -------------->|
             |                                                 | [TCP_NODELAY enabled]
             |                                                 |
             |-------- HELLO (Capabilities, Name, Model) ----->|
             |                                                 | [Assigns Session ID]
             |<------- HELLO_ACK (Status=0, SessionID) --------|
             |                                                 |
             |-------- VIDEO_CONFIG (H.264 SPS+PPS CSD) ------>|
             |                                                 | [VideoToolbox Configured]
             |                                                 |
             |-------- VIDEO_FRAME (Keyframe, PTS) ----------->|
             |                                                 | [Hardware Decompress to Metal]
             |-------- AUDIO_FRAME (PCM/AAC, PTS) ------------>|
             |                                                 | [CoreAudio Playback]
             |                                                 |
             |<------- HEARTBEAT (Echo RTT) ------------------>| [Monitors jitter & latency]
             |                                                 |
             |-------- DISCONNECT ---------------------------->|
             |                                                 | [Teardown session cleanly]
```

### 3.1 Handshake Steps
1. **TCP Connection**: Client connects to the receiver's port 27183. Receiver sets `TCP_NODELAY = true` to disable Nagle's algorithm.
2. **HELLO**: Client transmits device metadata (device model, manufacturer, display dimensions, platform capabilities).
3. **HELLO_ACK**: Receiver validates protocol version compatibility, assigns a unique session ID, and replies with `HELLO_ACK (status: 0 Accepted)`.
4. **VIDEO_CONFIG**: Client delivers H.264 parameter sets (CSD: SPS & PPS). The Mac initializes its `VTDecompressionSession`.
5. **Streaming**: High-frequency video and audio frames flow with monotonic timestamps.

---

## 4. VideoToolbox & Metal Rendering Integration

1. Incoming frames arrive on a high-priority interactive queue (`com.castsprint.mac.network.receiver`).
2. `VideoToolboxDecoder` wraps each frame in a `CMSampleBuffer` and submits it to Apple's dedicated hardware decompression engine.
3. The hardware decoder delivers a `CVPixelBuffer` in NV12 format (`420v`) directly to `MetalVideoRenderer`.
4. The Metal pipeline:
   - Preserves aspect ratio with automatic pillarboxing/letterboxing.
   - Converts NV12 (Y-plane, UV-plane) to BGRA within a hardware shader.
   - Renders directly onto a `CAMetalLayer` with VSync frame pacing.

---

## 5. Protocol Test Simulator (Receiver Verification)

To validate the macOS receiver independently of mobile hardware or during iOS app development, CastSprint includes a built-in **Protocol Test Simulator (`CastSprintTestSender`)**:
- Connects locally to `127.0.0.1:27183`.
- Negotiates the complete `CSP1` handshake with simulated iOS device capabilities (`CSP_CAP_PLATFORM_IOS`).
- Sends valid 1080p SPS/PPS parameter sets.
- Streams synthetic 60 FPS H.264 video and audio frames.
- Allows immediate verification of VideoToolbox hardware decoding, Metal rendering, HUD metrics, and audio subsystems.
- Clearly marked in the UI as **`Test-Only`**.
