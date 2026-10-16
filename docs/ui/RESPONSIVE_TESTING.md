# Responsive Testing Matrix

## Required viewports

- macOS: minimum window, 1280×720, 1920×1080; Retina and non-Retina.
- Windows: 100%, 125%, 150%, 200% DPI; multi-monitor moves.
- Linux: Wayland and X11, 1×/2× scaling after GUI exists.
- Android: 360×640 compact, large phone, tablet; portrait/landscape; font scale 1.0/1.3/2.0.
- iOS: smallest supported iPhone, current large iPhone, iPad; portrait/landscape; largest Dynamic Type.
- Website: 375, 768, 1024, 1440 CSS px; 200% zoom.

## Assertions

No toolbar overlap; essential labels remain available; focus is visible; scroll content clears fixed bars; video aspect ratio is stable; resizing does not restart capture; reduced motion removes nonessential transforms.

