# Metal Renderer Repair

The repaired renderer uses one consistent model: native `NSView` instances backed directly by `CAMetalLayer`, driven on incoming frames.

Pipeline: `CMSampleBuffer → CVPixelBuffer → CVMetalTextureCache → NV12/BGRA textures → Metal render pass → CAMetalDrawable → command-buffer completion`.

Important invariants:

- no `MTKView` delegate and no second Core Graphics live presenter;
- multiple output windows are separate weak Metal targets;
- aspect-fit viewport is calculated from drawable pixels;
- Retina drawable size follows the window backing scale;
- unsupported formats and nil drawables produce explicit telemetry errors;
- a frame is counted as presented only following successful GPU completion;
- texture wrappers remain alive through command completion;
- snapshot and one-frame diagnostics are opt-in CPU/Core Image paths.

Verification: debug and release Swift builds pass, app bundle signature validation passes. Physical iPhone presentation remains NOT_TESTED because no device was attached.
