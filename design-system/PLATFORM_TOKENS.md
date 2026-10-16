# Platform Token Mappings

All values derive from [MASTER.md](./MASTER.md). Native semantic colors must resolve dynamically when appearance changes.

| Semantic token | SwiftUI | Android | Windows | Linux | Next.js |
|---|---|---|---|---|---|
| Background | `Color.csBackground` | `colorScheme.background` | `CS_COLOR_BACKGROUND` | `cs-background` | `--cs-background` |
| Surface | `Color.csSurface` | `colorScheme.surface` | `CS_COLOR_SURFACE` | `cs-surface` | `--cs-surface` |
| Text Primary | `Color.csTextPrimary` | `onBackground` | `CS_COLOR_TEXT` | `cs-text-primary` | `--cs-text-primary` |
| Text Secondary | `Color.csTextSecondary` | `onSurfaceVariant` | `CS_COLOR_TEXT_MUTED` | `cs-text-secondary` | `--cs-text-secondary` |
| Accent | `Color.csAccent` | `primary` | `CS_COLOR_ACCENT` | `cs-accent` | `--cs-accent` |
| Border | `Color.csBorder` | `outlineVariant` | `CS_COLOR_BORDER` | `cs-border` | `--cs-border` |
| Focus | `.tint(.csAccent)` | focus indication | system focus + accent | toolkit focus | `--cs-focus` |

## Platform rules

- macOS/iOS: use semantic `Font` styles and environment color scheme. Keep the CAMetalLayer outside animated SwiftUI layout.
- Android: migrate screens incrementally to Material 3 Compose; keep capture/service objects outside composition and pass immutable snapshots.
- Windows: retain Win32/D3D11. Centralize DPI-scaled metrics and theme brushes; do not introduce WinUI merely for styling.
- Linux: GTK4/libadwaita is the recommended future shell because it supports Wayland, X11, HiDPI, accessibility, and system themes. It is not added until the decoded-frame renderer is functional.
- Website: CSS custom properties are canonical; use `next/image`, semantic HTML, reserved aspect ratios, and server components by default.

## Density

Desktop uses compact density without reducing hit targets. Mobile uses comfortable density. Telemetry may use tabular figures; user-facing labels use sentence case rather than all caps.

