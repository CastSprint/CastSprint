# Linux status

Overall: **STUB / BLOCKED**.

Implemented pieces: POSIX TCP listener, protocol parsing, pairing-token extraction, session callbacks and heartbeat response.

Missing pieces: TLS/AEAD, H.264 decoder, actual decoded frame buffers, X11/Wayland presentation, AAC/PCM decode, ALSA/PipeWire/PulseAudio output, A/V sync, UI, OBS verification, packaging and hardware testing.

The previous decoder copied encoded H.264 bytes into a field called `yuvData`, and audio returned success without output. Both now fail closed and log the missing backend. This prevents false streaming success but does not implement the receiver.

Local CMake build is BLOCKED because CMake is absent. No Linux artifact is claimed.
