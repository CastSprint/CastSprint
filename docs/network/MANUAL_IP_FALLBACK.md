# Manual IP fallback

Android provides host, port, fingerprint and token entry. It uses the identical pinned-TLS path as discovery; manual entry never enables plaintext or trust-all behavior. Status: **IMPLEMENTED_UNTESTED**, and currently **BLOCKED** because desktop TLS endpoints are incompatible.

QR pairing is MISSING. A future QR payload must be short-lived and bind receiver identity, address, protocol version and pairing session.
