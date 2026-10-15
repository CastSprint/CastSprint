# Metal Presentation Fix

The former view combined a child `CAMetalLayer` with a parent Core Graphics/Core Animation frame path and used a single replaceable presentation callback. The opaque child layer could cover the CPU image with black, while dashboard/OBS callback assignment could suppress coordinator state updates.

The repaired implementation uses one rendering model:

- `MirrorNativeDisplayView.makeBackingLayer()` returns the actual `CAMetalLayer`.
- Dashboard and gameplay windows register independent weak layer targets.
- Frames are retained as a bounded latest `CVPixelBuffer` for late layer attachment.
- NV12 video/full range and BGRA map through `CVMetalTextureCache`.
- Texture creation status, encoding, commit, GPU completion and errors are recorded.
- `PRESENTING_VIDEO`/rendering state begins only after successful Metal command completion.
- Core Image is limited to explicit PNG/screenshot conversion.

Build verification passes. Physical presentation remains **IMPLEMENTED_UNTESTED** until the diagnostic PNG and visible iPhone display are observed.
