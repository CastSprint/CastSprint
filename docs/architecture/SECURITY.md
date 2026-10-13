# Security & Privacy

## Principles
- No accounts, cloud, analytics, or telemetry. Core mirroring works fully offline.
- Screen contents never leave the user's local link (USB or LAN).
- Only documented Android APIs; capture requires explicit MediaProjection consent each session and a
  visible foreground-service notification. No permission bypasses, no root, no accessibility abuse.

## Threat model (v1)
| Threat | Mitigation |
|---|---|
| Malformed / hostile packets | Strict header validation before allocation; 64 KiB control / 8 MiB media caps; reject reserved bits; close on any error. Fuzzing planned (Phase 3). |
| Memory exhaustion | Bounded queues and pooled buffers; payload limits enforced before reads. |
| Unauthorized LAN viewer | Receiver listens; sender connects only to an address the user chose. **Phase 3:** pairing code shown on PC and typed on phone, then per-session key. |
| LAN eavesdropping | v1 traffic is unencrypted. USB (adb reverse) is local-only. **Phase 3:** TLS 1.3 or Noise-based encryption for LAN mode, keyed by pairing. Until then the UI must warn that LAN mode is unencrypted. |
| Exposure beyond LAN | Receiver binds to a user-selected interface; never uses UPnP / port forwarding. |

## Data handling
- Recordings are saved only to a user-selected local folder.
- Logs contain no frame data; device names appear only in local logs.
