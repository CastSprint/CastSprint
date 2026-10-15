# iPhone USB Regression

Status: **VERIFIED_WORKING** for video on the previously installed local build; current-source reinstall regression remains pending.

Physical iPhone 15 evidence collected on 2026-10-15:

- Native source format: `2vuy`
- Source dimensions observed: 1180×2556
- Capture rate observed: approximately 60 FPS
- Mirror View visibly showed real changing iPhone screen content
- Dedicated Gameplay window showed the same source
- Diagnostic PNG contained real screen imagery at 2556×1180:
  `~/Library/Logs/CastSprint/Diagnostics/source-frame-2026-10-15T10-55-14Z.png`

The original black screen was caused by the renderer accepting NV12/BGRA but not packed 4:2:2 `2vuy`. A CAMetalDrawable-backed Core Image path fixed it. The current source must be rebuilt/reinstalled and retested before claiming the latest artifact is verified.
