# Linux UI Audit

Framework: C++20 command-line receiver. No GUI toolkit is currently present.

| Area | Status | Evidence / issue | Required change |
|---|---|---|---|
| Receiver | IMPLEMENTED_UNTESTED | LAN server, decoder and audio objects exist | Build/test on Linux |
| Video output | NOT_IMPLEMENTED | Decoded-frame callback contains only `Forward decoded YUV to Wayland/X11 surface` comment | Implement real Wayland/X11-capable render surface |
| Desktop UI | NOT_IMPLEMENTED | `main.cpp` is CLI only | Add UI only after renderer architecture is selected |
| Theme/accessibility | NOT_IMPLEMENTED | No controls | GTK4/libadwaita is recommended for native theme, Wayland/X11 and a11y |
| OBS output | NOT_IMPLEMENTED | No stable gameplay window | Implement and verify real pixels before presenting UI controls |

A polished shell must not conceal the missing renderer. GTK4/libadwaita is the lowest-risk current direction, but dependency introduction needs a Linux build environment and packaging review.

