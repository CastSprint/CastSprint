# Memory-pressure safety

The live pipeline now prefers freshness over backlog.

| Stage | Bound | Overload behavior |
|---|---:|---|
| AVCapture video | latest frame | discard late frames |
| Metal renderer | 3 command buffers | drop render submission |
| CAMetalLayer | 2 drawables | timed drawable acquisition |
| Audio output | 12 PCM buffers | drop incoming buffer |
| Recording video | 3 samples | drop incoming sample |
| Recording audio | 12 samples | drop incoming sample |

The bounds prevent producer speed from causing indefinite memory growth. **NOT_TESTED:** post-fix peak memory during physical-device gameplay; capture it with Activity Monitor and Instruments using the safe test plan.

