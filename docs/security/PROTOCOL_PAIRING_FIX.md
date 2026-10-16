# Protocol pairing fix

Root cause: senders and receivers had no consistent token field. Android encoded `deviceName|token`; Windows/Linux compared the entire string to the PIN; macOS accepted HELLO without validating a token; iOS did not send one.

Implemented:

- six-digit per-session token on macOS;
- no PIN in Bonjour TXT or logs;
- sender convention `displayName|token` for protocol v1 compatibility;
- token extraction before the clean device name is displayed;
- macOS constant-time comparison and pre-auth packet rejection;
- Windows/Linux pre-auth rejection and token-only `ProcessHello` input;
- nonzero random session ID only after authentication;
- iOS rejects missing or malformed tokens;
- the test sender authenticates through the same path.

Limitations: protocol v1 still places the token inside a plaintext HELLO on Apple/Linux transports. This prevents accidental/wrong-peer connection but is not secure pairing on a hostile network. Do not reuse this token as a long-term device credential.

Validation: macOS release build PASS. Native session tests PASS (19 checks). Cross-device handshake is IMPLEMENTED_UNTESTED.
