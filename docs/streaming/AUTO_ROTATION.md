# Automatic Rotation

Auto is the default. `MetalVideoRenderer` reports actual frame-dimension changes. The existing gameplay `NSWindow` is resized to the new aspect ratio without restarting capture or replacing the window. Dimensions are not hard-coded and are constrained to 72% of the current display's visible area.

Manual mode preserves user geometry. Fixed canvas presets preserve canvas aspect while the frame remains aspect-fit. Physical ten-rotation testing is pending.
