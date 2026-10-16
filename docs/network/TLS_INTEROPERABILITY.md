# TLS interoperability

Verdict: **FAILED — P0 release blocker**.

- Android: JSSE TLS client with SHA-256 leaf-certificate pinning.
- macOS: plaintext Network.framework listener.
- Windows: SChannel credentials created, but raw socket I/O remains outside SChannel records.
- Linux: plaintext socket.

Consequently Android Wi-Fi cannot interoperate securely with any current desktop receiver. USB Gaming is intentionally separate: plaintext application packets travel only through authenticated ADB reverse loopback and still require the session token. This exception must never be exposed on a LAN socket as a Wi-Fi fallback.
