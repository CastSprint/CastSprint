# Pairing protocol

Protocol v1 compatibility currently carries a six-digit ephemeral token as `deviceName|token`; receivers extract it before displaying the clean name and reject pre-auth media. USB desktop provisioning passes the token via an explicit ADB activity extra.

Status: **IMPLEMENTED_UNTESTED**, not a final cryptographic pairing design. On Wi-Fi the token must be bound to the verified TLS receiver identity, expire, be single-session, resist replay, and migrate to an explicit protocol-v2 field. The current Apple/Linux plaintext transport does not satisfy this requirement.
