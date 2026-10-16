# CastSprint Design System

Status: canonical cross-platform specification  
Theme default: System  
Design intent: premium, quiet, fast, creator-focused, native

## Principles

1. Show transport truth. `Streaming` means a real frame reached a renderer; `Connected` means authentication completed.
2. Keep gameplay visually dominant. Controls are compact, stable, and never enter the clean OBS output.
3. Preserve native behavior. Share tokens and language, not framework code.
4. Spend GPU time on media, not decoration. No continuous gradients, WebGL, or persistent blur.
5. Every failure includes the next safe action.

The `ui-ux-pro-max` generator suggested a high-cost 3D gaming treatment and purple palette. Those recommendations were rejected because they conflict with CastSprint's required cyan/blue identity, native-platform conventions, accessibility, and low-overhead goal. Its guidance for visible focus, recovery actions, reduced motion, adaptive layouts, and semantic controls is adopted.

## Brand primitives

| Token | Value | Purpose |
|---|---:|---|
| `cyan-500` | `#06D4FF` | Brand accent, focus, active navigation |
| `blue-600` | `#137EFF` | Primary action gradient endpoint / links |
| `navy-950` | `#06111C` | Dark elevated surface |
| `ink-1000` | `#030A13` | Dark background |
| `cloud-50` | `#F6FBFF` | Light background |
| `white` | `#FFFFFF` | Dark-theme primary text |
| `slate-950` | `#0B1724` | Light-theme primary text |
| `slate-600` | `#526274` | Light-theme secondary text |
| `slate-400` | `#94A3B8` | Dark-theme secondary text |
| `green-500` | `#22C55E` | Verified success / rendering |
| `amber-500` | `#F59E0B` | Waiting / degraded |
| `red-500` | `#EF4444` | Failure / destructive action |

## Semantic colors

| Role | Light | Dark |
|---|---|---|
| Background | `#F6FBFF` | `#030A13` |
| Surface | `#FFFFFF` | `#06111C` |
| Surface Elevated | `#FFFFFF` | `#0B1724` |
| Text Primary | `#0B1724` | `#F6FBFF` |
| Text Secondary | `#526274` | `#A9B8C8` |
| Border | `#CFDCE8` | `#243648` |
| Accent | `#007DA3` | `#06D4FF` |
| On Accent | `#FFFFFF` | `#001A23` |
| Success | `#15803D` | `#4ADE80` |
| Warning | `#A15C00` | `#FBBF24` |
| Error | `#C62828` | `#FF6B6B` |
| Disabled text | `#8493A3` | `#6F8091` |
| Focus ring | `#137EFF` | `#06D4FF` |

Color is never the only state cue. Status always has text and, where useful, an icon. Accent cyan is not body text on light backgrounds.

## Typography

Use the platform system font: SF Pro on Apple platforms, Segoe UI Variable on Windows, system UI on Android, and the active desktop system sans on Linux. The website uses its existing optimized local/system stack. Monospace is reserved for PINs, addresses, codecs, and telemetry.

| Style | Size | Line height | Weight |
|---|---:|---:|---:|
| Display | 40 | 48 | 700 |
| Title 1 | 28 | 34 | 700 |
| Title 2 | 22 | 28 | 650 |
| Title 3 | 18 | 24 | 600 |
| Body | 16 | 24 | 400 |
| Body compact | 14 | 20 | 400 |
| Label | 13 | 18 | 600 |
| Caption | 12 | 16 | 500 |
| Telemetry | 12 | 16 | 600 mono/tabular |

Native apps must prefer semantic/scalable styles over fixed sizes. Web text supports at least 200% zoom without loss of function.

## Geometry and spacing

- Base unit: 4.
- Spacing: 4, 8, 12, 16, 24, 32, 48, 64.
- Radius: 6 controls, 10 cards, 14 dialogs, pill only for status/chips.
- Control height: macOS 32/36; Windows 32/40; iOS 44 minimum; Android 48dp minimum; web 40/44.
- Icons: 16, 20, 24; 32 only for empty states.
- Content width: 1280 desktop dashboard, 720 forms/docs, fluid mobile with 16-point gutters.
- Shadows: one low elevation and one dialog elevation; borders provide most hierarchy.

## Motion

- Instant state feedback: 80–120 ms.
- Component transitions: 160–220 ms.
- Sheets/dialogs: native platform motion, normally 220–300 ms.
- Never animate live video geometry continuously.
- Reduced Motion disables nonessential transforms and scroll reveals.
- Loading indicators stop when work stops; no decorative infinite animation.

## Responsive layout

- Compact: under 640 px/pt — one column, bottom or native tab navigation, overflow actions grouped.
- Regular: 640–1023 — collapsible two-column dashboard.
- Wide: 1024+ — device rail + primary work area; preview maintains source aspect ratio.
- Toolbars wrap into logical groups; labels never collapse into unexplained ellipses.
- Resizing never restarts capture or recreates the media session.

## State vocabulary

`Available` → `Connecting` → `Pairing` → `Authenticated` → `Waiting for video` → `Receiving video` → `Rendering` → `Audio active`.

Use `Reconnecting`, `Disconnected`, and `Error` explicitly. Do not use `Ready` to imply a phone is connected. `Streaming` is reserved for changing frames rendered successfully.

## Breakpoints and verification

Website: 375, 768, 1024, 1440 CSS px. Android/iOS: small phone, large phone, tablet in portrait and landscape with maximum supported text size. Desktop: minimum supported window, 1280×720, 1920×1080, HiDPI/multiple displays. All themes: Light, Dark, System; default System.

