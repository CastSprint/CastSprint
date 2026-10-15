# Multi-output render cost

Main Preview and `CastSprint — Gameplay` are independent Metal targets. When both are visible, each target performs presentation work, so GPU cost is expected to increase.

The OBS target now detaches while its window is hidden or closed. Opening it reattaches the target without replacing the preview callback. This removes invisible duplicate rendering while preserving independent presentation.

**NOT_TESTED:** exact GPU and memory delta for one output versus two. Measure both cases with identical source content and duration.

