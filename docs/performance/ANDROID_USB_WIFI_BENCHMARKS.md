# Android USB/Wi-Fi benchmarks

No hardware measurements were taken because `adb devices -l` returned no device. Capture, encode, transport, decode and render FPS; median/p95 latency; CPU/GPU/RAM; battery; jitter; drops and audio underruns are **BLOCKED**.

The implementation uses bounded video/audio queues and verified ADB reverse rather than an unbounded retry path. These design properties are not benchmark results.
