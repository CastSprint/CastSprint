# OBS Integration

Use OBS 32.0.4 `macOS Screen Capture` in Window Capture mode and select **CastSprint — Gameplay**. Do not select **CastSprint — Gaming View**, which is the control interface. The gameplay window has a stable `NSWindow` identity and contains only its Metal surface.

Implemented: source-driven resizing, stable window reuse, independent renderer target, source-native/16:9/9:16 canvases, separate OBS FPS. Unverified: hidden/minimized capture and completed OBS recordings with this build.
