# Black Screen Root Cause — 2026-10-15

## Real-hardware update

The iPhone 15 delivered `2vuy` packed UYVY 4:2:2 at 1180×2556 and approximately 57 captured FPS. The renderer had no `kCVPixelFormatType_422YpCbCr8` branch, producing zero rendered FPS. Version 0.2.2 adds a persistent Metal-backed Core Image conversion directly to each drawable. See `2VUY_PIXEL_FORMAT_FIX.md`.

## Evidence

The pre-existing working tree incremented its live state from capture callbacks and then attempted two simultaneous presentation mechanisms in `MirrorNativeDisplayView`:

1. a child `CAMetalLayer` attached to the renderer; and
2. a Core Image-to-`CGImage` result assigned to the parent layer and drawn with Core Graphics.

The opaque child Metal layer could cover the parent layer's image with an unrendered black surface. In addition, `MetalVideoRenderer` had one mutable `onFramePresented` closure. The coordinator, dashboard view, and OBS window each replaced it, so state notification and frame delivery depended on construction order. Capture samples were also counted again inside the renderer, corrupting capture FPS.

This is a code-proven rendering ownership defect. The earlier `.video` versus `.muxed` device-selection defect and forced pixel-format defect had already been addressed in the branch. No physical phone was attached during this audit, so the exact on-device visual result remains **IMPLEMENTED_UNTESTED**, not VERIFIED_WORKING.

## Repair

- `MirrorNativeDisplayView.makeBackingLayer()` now returns the sole `CAMetalLayer`.
- Removed the child layer and competing Core Graphics live-display path.
- The renderer keeps weak independent targets for the dashboard and `CastSprint — Gameplay` window.
- Live frames remain GPU-only through `CVMetalTextureCache`; Core Image is used only for explicit screenshot/diagnostic export.
- NV12 uses actual plane dimensions; BGRA remains direct.
- Pixel conversion, drawable acquisition, encoding, commit, GPU completion, failure and presented FPS are tracked separately.
- The app enters `RENDERING` only after a command buffer completes successfully.
- A one-shot opt-in diagnostic saves the next real source frame and metadata to `~/Library/Logs/CastSprint/Diagnostics`.

## Required acceptance run

Connect and unlock the iPhone, start USB mirroring, show the Home Screen, click **Settings → Capture Next Source Frame**, and inspect the PNG. Then confirm both the dashboard and `CastSprint — Gameplay` window animate. Record capture FPS, render FPS, pixel format, audio behavior, rotation, reconnect, OBS and Streamlabs results. Until that run is completed, black-screen closure is not a PASS.
