# Wireless Security Audit

Status: **FAILED** (release blocking)

Date: 2026-10-15

`NetworkStreamReceiver` currently constructs `NWParameters(tls: nil, tcp: ...)`. The pairing PIN and protocol handshake therefore do not provide transport confidentiality or independently authenticated device identity. Media sent on an untrusted LAN can be observed or modified.

Required before wireless release:

- TLS or an audited authenticated-encryption session layered over the transport.
- PIN-bound key agreement that authenticates both peers.
- Persisted device identity with explicit trust/revocation controls.
- Replay protection and sequence validation.
- Strict negotiated packet-size and codec limits before allocation/decoding.
- Authentication must complete before UI state becomes connected; a rendered frame is required before state becomes streaming.

Until implemented and tested, Android/iPhone Wi-Fi mirroring is development-only and must not be represented as secure.
