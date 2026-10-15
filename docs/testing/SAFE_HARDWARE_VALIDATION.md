# Safe hardware validation

Because the previous build contributed to system-wide VM exhaustion, validation must be incremental.

## Preconditions

- Save unrelated work.
- Reboot after the panic if memory pressure remains elevated.
- Keep Activity Monitor's Memory and GPU views visible.
- Begin with OBS closed and phone audio disabled.

## Sequence

1. Launch CastSprint idle for one minute; record memory/CPU.
2. Connect the unlocked iPhone and run video-only for 30 seconds.
3. Continue for two minutes only if memory is bounded.
4. Open the OBS gameplay window for two minutes.
5. Open OBS and capture the gameplay window for two minutes.
6. Enable phone audio last and repeat for two minutes.
7. Stop mirroring, close the OBS window, and verify resource recovery.

## Abort criteria

Immediately stop CastSprint if resident memory climbs without stabilizing, memory pressure becomes yellow/red, swap rapidly increases, the system becomes unresponsive, or watchdog/GPU errors appear. Preserve logs before retrying.

Passing this short test permits a later 10-minute test. It does not by itself establish long-duration stability.
