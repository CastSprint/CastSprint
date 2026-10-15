# 2vuy Pixel Format Fix

Real iPhone 15 evidence showed valid capture at approximately 57 FPS, 1180×2556, FourCC `2vuy`, while rendered FPS remained zero. `MetalVideoRenderer` only handled NV12 and BGRA, making packed UYVY 4:2:2 the first failed pipeline stage.

Version 0.2.2 adds a persistent Metal-backed `CIContext` path for `kCVPixelFormatType_422YpCbCr8`. Core Image consumes the source pixel buffer and its YCbCr attachments, applies aspect-fit composition, and writes directly into each `CAMetalDrawable` texture. The layer is non-framebuffer-only for GPU writes. There is no CPU color conversion or per-frame context creation. Existing NV12/BGRA texture-cache paths remain unchanged.

Build and install verification pass. Physical presentation on 0.2.2 remains pending because the iPhone was not enumerated after relaunch.
