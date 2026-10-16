# Android Wi-Fi connection guide

Status: **FAILED/BLOCKED** for release.

Android discovery and manual pairing exist, but Android requires pinned TLS while macOS/Linux listen in plaintext and Windows does not apply its SChannel credentials to media I/O. Do not disable pinning or use a trust-all certificate.

Until a compatible desktop TLS server is implemented, use USB Gaming. Manual host entry does not bypass the same TLS and identity checks.
