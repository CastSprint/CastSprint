# Implementation gaps

## P0 release blockers

1. **End-to-end TLS/AEAD is MISSING.** Pairing now rejects a wrong token, but Apple and Linux media remain plaintext. Windows creates SChannel credentials without running the SChannel record handshake.
2. **Linux media receiver is a STUB.** No FFmpeg/VA-API decode, SDL/OpenGL/Vulkan display, ALSA/PipeWire/PulseAudio output, or A/V clock exists.
3. **Windows integration is PARTIAL.** It needs a real SChannel stream, tested Media Foundation decode, D3D presentation, WASAPI audio, and physical Windows verification.
4. **Cross-platform audio needs hardware validation.** macOS AAC decode is implemented but has not been exercised against Android/iOS senders.
5. **iOS signed device delivery is BLOCKED.** Full Xcode, a team/profile, extension entitlement, and physical install are required.

## P1 gaps

- Token expiry, trust persistence/revocation, replay window, and rate limiting.
- Golden handshake/authentication vectors shared by Swift, Kotlin and C++.
- Bounded reconnect strategy and multi-peer policy across all receivers.
- Native Windows/Linux UI parity and OBS/Streamlabs recording verification.
- Automated artifact signing/notarization and release checksums on protected tags.

No existing UI label or successful compile closes these gaps.
