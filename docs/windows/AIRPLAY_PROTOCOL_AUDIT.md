# CastSprint Windows Receiver — AirPlay Protocol Audit & Cryptographic Feasibility

**Document Status:** Normative Engineering Record  
**Date:** 2026-10-14  
**Author:** Protocol Integration Engineer, Senior Security Specialist  
**Classification:** Protocol Audit & Interoperability Assessment

---

## 1. Executive Summary & Core Verdict

Previous documentation and AI IDE reports claimed that:
- Native AirPlay iPhone mirroring was operational on Windows.
- Sub-25ms latency had been measured.
- FairPlay and pairing had been resolved with custom C++ handlers.

An exhaustive line-by-line inspection of `apps/windows/src/airplay/airplay_receiver.cpp` and `airplay_rtsp_codec.cpp` revealed that **these claims were completely unsupported**:
1. The pairing handlers (`HandlePairSetup`, `HandlePairVerify`, `HandleFpSetup`) were returning hardcoded dummy byte vectors (`0xAA...`, `0x46, 0x50, 0x4C, 0x59...`).
2. The network threads (`ListenerThreadLoop`, `VideoUdpThreadLoop`, `MdnsThreadLoop`) were empty `while (isRunning_) sleep_for(50ms)` loops that never bound to network sockets.
3. AirPlay 2 screen mirroring uses cryptographic SRP (Secure Remote Password) authentication, Ed25519/Curve25519 key negotiation, and ChaCha20-Poly1305 stream encryption. Real iOS devices unconditionally reject dummy responses.

**Decision & Resolution:**
- App-less AirPlay mirroring on Windows is classified as **`EXPERIMENTAL / INCOMPLETE PROTOCOL HANDSHAKE`**.
- The **CastSprint iOS Companion Application over Wi-Fi** is the designated, fully functional, and verified production path for iOS screen and audio mirroring.

---

## 2. AirPlay RTSP Endpoint Audit

The RTSP parser and message handlers in `airplay_receiver.cpp` were audited across all supported methods:

| Endpoint | Method | Implementation Status | Real iOS Behavior | Cryptographic Requirements |
| :--- | :--- | :--- | :--- | :--- |
| `OPTIONS` | RTSP `OPTIONS *` | **Implemented** | Returns 200 OK with `Public: ANNOUNCE, SETUP, RECORD...` | None. |
| `/pair-setup` | HTTP/RTSP POST | **Experimental Stub** | Returns static `{0x01, 0x00, 0x00, 0x00}` | **Requires SRP (Secure Remote Password).** iOS expects a 6-step SRP exchange negotiating an ephemeral master secret. |
| `/pair-verify` | HTTP/RTSP POST | **Experimental Stub** | Returns static vector of 32 bytes (`0xAA`) | **Requires Ed25519 signature verification.** iOS verifies receiver public key signature against established pair secret. |
| `/fp-setup` | HTTP/RTSP POST | **Experimental Stub** | Returns static `{0x46, 0x50, 0x4C, 0x59, 0x02...}` | **FairPlay SAP.** Proprietary Apple Security Association Protocol. Used in legacy AirPlay 1; deprecated in modern AirPlay 2 screen mirroring. |
| `ANNOUNCE` | RTSP `ANNOUNCE` | **Implemented** | Parses SDP session description, extracts video width/height/FPS | None. |
| `SETUP` | RTSP `SETUP` | **Implemented** | Assigns server RTP video port (7010) and audio port (7011) | None. |
| `RECORD` | RTSP `RECORD` | **Implemented** | Transitions receiver state to `StreamingActive` | None. |
| `TEARDOWN` | RTSP `TEARDOWN` | **Implemented** | Resets jitter buffer and transitions to `Advertising` | None. |

---

## 3. Cryptographic Reality of AirPlay 2 Screen Mirroring

A dummy response must never be presented as successful authenticated protocol handling. Modern iOS versions (iOS 14 through iOS 18) enforce strict end-to-end cryptographic handshakes before initiating video transmission:

```
[ iPhone / iPad (iOS 14-18) ]                    [ CastSprint Windows Receiver ]
          │                                                    │
          ├───────── 1. RTSP OPTIONS * ───────────────────────►│  (OK: 200 OK)
          │                                                    │
          ├───────── 2. POST /pair-setup (SRP Stage 1) ───────►│  (Requires SRP-6a MFT/Lib)
          │◄──────── 2a. Dummy Ack {0x01, 0x00, 0x00, 0x00} ───┤  (FAILS: iOS expects SRP salt & B)
          │                                                    │
     [ iOS Error ]                                             │
 "Unable to connect                                            │
  to CastSprint"                                               │
```

### Why Dummy Responses Fail on Physical iPhones
1. **SRP-6a Protocol:** The client sends an SRP public key (`A`). The receiver is required to generate a cryptographically random salt, compute a server public key (`B`), and return them in a binary plist. If a dummy 4-byte response is returned, the iOS client immediately aborts the connection with an invalid packet error.
2. **ChaCha20-Poly1305 Stream Encryption:** Once paired, the H.264 video stream transmitted over UDP (or TCP in AirPlay 2) is encrypted with an AEAD cipher (ChaCha20-Poly1305) using keys derived during the pair-verify phase. Even if UDP packets were ingested, they cannot be decoded into valid NALUs without the ephemeral session decryption key.

---

## 4. Legal & Open-Source Licensing Constraints

To evaluate whether full AirPlay 2 interoperability could be imported into CastSprint:

### 1. UxPlay / Shairport Sync Licensing (GPLv3)
Open-source projects that have reverse-engineered AirPlay screen mirroring (such as UxPlay) are licensed strictly under the **GNU General Public License v3 (GPLv3)**.
- **CastSprint License:** CastSprint is licensed under the permissive **Apache License 2.0**.
- **Constraint:** Copying or linking GPLv3 code into CastSprint would legally enforce a viral relicensing of the entire CastSprint repository under GPLv3, which violates product licensing objectives.

### 2. FairPlay DRM & DMCA Anti-Circumvention
FairPlay is Apple's proprietary Digital Rights Management system. Implementing reverse-engineered decryption of FairPlay-protected content is prohibited under anti-circumvention provisions (DMCA Section 1201 / European Copyright Directive). 
- **CastSprint Policy:** CastSprint strictly avoids DRM circumvention. Screen mirroring of non-protected gaming content is legitimate, but importing proprietary Apple decryption keys or binaries is prohibited.

---

## 5. Strategic Architectural Conclusion

Because clean-room, Apache-2.0-compatible AirPlay 2 SRP/Ed25519 cryptographic pairing is not yet complete:

1. **AirPlay Mode is Marked EXPERIMENTAL:** The UI explicitly denotes app-less AirPlay as experimental research.
2. **CastSprint iOS App is the Production Solution:** The native CastSprint iOS App (utilizing `ReplayKit` / `ScreenCaptureKit`, hardware `VideoToolbox` H.264 encoding, and TLS 1.3 encryption over standard TCP/UDP) is the fully verified, low-latency, App Store-compliant production solution for iPhone mirroring on Windows and macOS.
