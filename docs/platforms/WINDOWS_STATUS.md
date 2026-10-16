# Windows status

Overall: **PARTIAL / BLOCKED**.

The C++ receiver parses the protocol, authenticates the extracted pairing token, and contains Media Foundation, D3D11 and WASAPI components. No Windows host was available in this audit, so compilation, GUI smoke, hardware decode, renderer, audio, OBS and installer are not verified.

Critical defect: SChannel credentials are initialized, but `HandleClient` reads/writes plaintext TCP directly. This is not TLS. The receiver must fail release security gates until a complete SChannel handshake and encrypted record loop replaces raw media I/O.

No physical Windows result, executable, signature or installer is claimed.
