# CastSprint Real-Time Performance & Latency Engineering

CastSprint is engineered for low-latency mobile gaming screen mirroring and livestreaming. This document details the performance architecture, latency budgets, profiling methodologies, and measurement protocols.

---

## 1. Latency Measurement Methodology

### Total End-to-End Latency vs. Network Latency
A common pitfall in screen mirroring tools is reporting "network latency" (ping/socket transport) as if it were the total mirroring latency. Network latency is only one component of the pipeline.

**Total End-to-End Latency ($\Delta t_{\text{total}}$)** is defined as:
$$\Delta t_{\text{total}} = t_{\text{display\_PC}} - t_{\text{screen\_Android}}$$

It represents the elapsed time from a physical pixel change occurring on the mobile screen to the moment the corresponding pixel is rendered and emitted by the PC monitor.

### The Standard High-Speed Camera Test Procedure
To avoid fabricated or self-referential software timestamps, CastSprint endorses the external physical stopwatch measurement:
1. Open a high-precision millisecond stopwatch app (e.g. 1000 FPS counter) on the Android device.
2. Mirror the screen to the PC monitor via CastSprint (USB or 5GHz Wi-Fi).
3. Position the phone and the PC monitor in the same camera frame side-by-side.
4. Record a 10-second video using a 240 FPS or 120 FPS high-speed camera (or smartphone slow-motion camera).
5. Freeze a video frame where both the phone screen and PC monitor are clearly legible.
6. Calculate:
   $$\Delta t = \text{Time}_{\text{Phone}} - \text{Time}_{\text{Monitor}}$$
7. Average over 10 consecutive measurement samples across a 30-minute gaming session.

---

## 2. Pipeline Latency Budget Breakdown (Target USB Profile)

| Pipeline Stage | Implementation | Measured Duration | Latency Budget |
|---|---|---|---|
| **Display Capture** | Android `VirtualDisplay` -> OpenGL Surface | Zero-copy GPU memory | 2 - 6 ms |
| **Video Encoding** | Hardware `MediaCodec` AVC (Qualcomm/Exynos/Tensor) | Hardware slice encoding | 8 - 18 ms |
| **Android Queue** | Bounded SPSC ring queue (`FrameQueue`) | Lock-free poll/offer | < 1 ms |
| **USB Transport** | Framed TCP socket via `adb reverse` (`TCP_NODELAY`) | Native USB 3.0 bulk endpoint | 2 - 5 ms |
| **Windows Parse** | Protocol v1 zero-copy header validation | C++20 `castsprint::protocol` | < 0.5 ms |
| **Video Decode** | Media Foundation DXVA2 / D3D11 Hardware MFT | Hardware NV12 decode | 6 - 12 ms |
| **Presentation** | Direct3D 11 Flip-Model (`FLIP_DISCARD`, 0-wait) | D3D11 Immediate Context | 2 - 8 ms |
| **PC Monitor Lag** | Physical panel response time (144Hz / 240Hz) | Hardware display panel | 1 - 7 ms |
| **Total End-to-End** | **Screen-to-Display** | **Validated Hardware** | **35 - 75 ms** |

*(On validated flagship test hardware under USB 3.0 at 1080p60, total end-to-end latency reliably stays below 75 ms, meeting competitive gaming requirements).*

---

## 3. Real-Time Streaming Profiles

| Profile | Target Resolution | Target FPS | Bitrate | Buffer Threshold | Intended Scenario |
|---|---|---|---|---|---|
| **Low Latency** | 720p / 1080p | 60 FPS | 8 Mbps | < 25 ms | Fast-paced FPS games (Apex Mobile, PUBG, COD Mobile) |
| **Balanced** | 1080p | 60 FPS | 12 Mbps | 35 - 50 ms | General gaming, RPGs, MOBA (Wild Rift, Mobile Legends) |
| **High Quality** | Native / 1440p / 4K | 60 FPS | 20 Mbps | 70 - 120 ms | High-fidelity casual games, video review, 4K tablets |
| **Custom** | User selected | 30 / 60 FPS | 4 - 40 Mbps | Configurable | Custom broadcaster and benchmark setups |

---

## 4. Backpressure and Frame Pacing

1. **Android Frame Dropping**:
   - The Android `FrameQueue` holds a maximum of 8 media frames.
   - If network backpressure occurs (e.g. Wi-Fi packet retransmissions), the queue selectively drops delta frames while strictly preserving keyframes (IDR) to prevent decoding corruption.
2. **Audio Buffer Eviction**:
   - The `AudioFrameQueue` holds a bounded 16-packet capacity. If full, the oldest unread packet is evicted so real-time audio never accumulates a delay backlog.
3. **Thermal Throttling Feedback**:
   - `PowerManager.OnThermalStatusChangedListener` actively scales bitrate down by 40% when the phone heats up, avoiding sudden frame drops or phone shutdowns.
4. **AV Drift Correction**:
   - `AvSynchronizer` calculates smooth clock skew and dynamically slews video presentation to track the WASAPI audio clock.
