# End-to-end TLS validation

Status: **FAILED — release blocking**.

| Path | Observation | Status |
|---|---|---|
| Android sender | TLS socket with pinned receiver fingerprint | BUILD_ONLY |
| macOS receiver | Network.framework configured with `tls: nil` | MISSING |
| iOS sender | Network.framework configured with `tls: nil` | MISSING |
| Windows receiver | SChannel credential exists; media socket uses raw `recv`/`send` | STUB |
| Linux receiver | raw TCP | MISSING |

No compatible encrypted end-to-end sender/receiver pair was demonstrated. Therefore certificate pinning, downgrade resistance, record integrity, replay behavior, expiry/revocation, and reconnect identity were not validated.

Required acceptance: TLS 1.3 (or an audited Noise-style authenticated channel), receiver identity fingerprint shown out-of-band, PIN-bound authentication, strict certificate verification, sequence/replay controls, packet-size limits, negative tests, packet capture showing no plaintext HELLO/media, and physical cross-platform runs.
