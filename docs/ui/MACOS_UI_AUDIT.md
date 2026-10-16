# macOS UI Audit

Framework: SwiftUI shell + AppKit windows + CAMetalLayer renderer. Source: `DashboardView.swift` (910 lines).

| Area | Status | Evidence / issue | Required change |
|---|---|---|---|
| Navigation | WORKING / INCONSISTENT | Home, Mirror, Settings preserve coordinator state; fixed horizontal header can collide at small widths | Adaptive toolbar/overflow and native labels |
| Theme | BROKEN | Hard-coded dark colors; no Light/System mapping | Semantic dynamic tokens, System default |
| Type | INACCESSIBLE | Many fixed 8–15 pt fonts and all-caps labels | Semantic fonts, wrap essential labels |
| Devices | WORKING / NEEDS QA | Real coordinator list and refresh exist | Group USB/Wireless/Advanced; stable selection feedback |
| Mirror | WORKING / NEEDS HARDWARE | Metal preview and OBS target are real | Preserve renderer; group controls; truthful render failure |
| States | WORKING | Detailed session-state mapping exists | Human-readable sentence case; avoid internal enum-like text |
| Resize | BROKEN | Fixed single-row controls shown overlapping in evidence screenshots | Responsive layout and overflow menu |
| Accessibility | PARTIAL | Some identifiers/labels exist | Complete labels, keyboard order, focus and reduced motion |

Build/physical verification is recorded in `FINAL_QA_REPORT.md`; UI audit does not certify hardware behavior.

