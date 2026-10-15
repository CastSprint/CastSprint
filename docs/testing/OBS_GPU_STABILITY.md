# OBS GPU stability test

Status: **NOT_TESTED** on the repaired build.

Staged test:

1. Establish a stable single-window iPhone mirror for two minutes.
2. Record CastSprint memory, GPU, render FPS, and backpressure drops.
3. Open `CastSprint — Gameplay`; repeat for two minutes.
4. Add only that window to OBS; repeat for two minutes.
5. Close/reopen the gameplay window and verify preview continuity.
6. Stop capture and confirm memory returns toward baseline.

Abort if memory grows continuously, swap pressure rises, the UI stalls, or render FPS becomes zero. Do not run a long soak until this short progression is stable.

