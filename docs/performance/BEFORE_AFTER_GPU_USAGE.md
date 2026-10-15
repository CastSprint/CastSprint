# Before/after GPU usage

## Before

**VERIFIED FROM PANIC SNAPSHOT:** CastSprint reached 20.13 GB resident memory in about 6.2 minutes. The renderer had no explicit in-flight GPU bound.

## After (source-level)

**VERIFIED:** three-command-buffer admission limit, two-drawable layers, timeout-enabled drawable acquisition, backpressure-drop telemetry, and hidden-output detachment are implemented.

## Measurements

Post-fix GPU percentage, renderer time, energy impact, and peak resident memory are **NOT_TESTED**. The prior and repaired builds must not be compared using invented numbers. Record measurements during the staged hardware test.

