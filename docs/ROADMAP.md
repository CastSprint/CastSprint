# Roadmap

| Phase | Goal | Key deliverables |
|---|---|---|
| **1 — Foundation** ✅ | Buildable skeleton | Protocol v1 spec + C++ codec + tests, Win32/D3D11 shell, Android shell, docs, CI |
| **2 — First pixels (USB)** | End-to-end video | Android foreground service + MediaProjection + MediaCodec H.264 + TCP sender; Windows Winsock server, MF H.264 decoder (D3D11), NV12 render, aspect-correct letterbox; `adb reverse` helper |
| **3 — Robustness & LAN** | Reliable sessions | Heartbeats, reconnection, rotation/resolution changes, keyframe requests, bounded-queue drop policy, LAN discovery (mDNS/manual IP), pairing + encryption, codec fuzzing |
| **4 — Audio** | Game audio | AudioPlaybackCapture (Opus/AAC via MediaCodec), WASAPI output, A/V sync |
| **5 — Gaming & OBS** | Creator features | Low-latency present (tearing, waitable swap chain), FPS/bitrate presets (60/90/120), fullscreen/borderless, always-on-top, local recording (remux), stats overlay toggle |
| **6 — Polish** | Release | Installer (MSIX/WiX), signed builds, settings UI (WinUI 3 evaluation), localization, donation link (voluntary) |
| **Future** | Platforms | macOS receiver (VideoToolbox/Metal), iOS sender research, H.265/AV1 |

Measurement-driven: every latency/FPS claim requires a reproducible measurement on named hardware.
