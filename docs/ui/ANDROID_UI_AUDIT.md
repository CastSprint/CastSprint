# Android UI Audit

Framework: one native Kotlin `Activity` building programmatic `LinearLayout`, `TextView`, and `Button` views. Capture, encoder, transport, and foreground service are separate and must be preserved.

| Area | Status | Evidence / issue | Required change |
|---|---|---|---|
| Capture workflow | WORKING / UNVERIFIED | MediaProjection permission and real service flow exist | Keep service boundary; validate on device |
| Navigation | MISSING | 1,088-line activity constructs the whole UI | Incremental Material 3 Compose screen shell |
| Responsive layout | BROKEN | Manual rows/grids and fixed sizing risk overflow | Window-size-aware one/two-pane layouts |
| Theme | INCONSISTENT | Styling is imperative and not token-driven | Material 3 dynamic semantic scheme; System default |
| Accessibility | PARTIAL | Native controls help, but hierarchy/labels/scaling are incomplete | TalkBack labels, headings, 48dp targets, font-scale tests |
| Devices/pairing | WORKING / COMPLEX | Discovery, saved pairing, USB token and manual configuration exist | Wizard with explicit USB/Wi-Fi paths and recovery |
| Performance | NEEDS QA | Stats intentionally update every 500 ms | Immutable UI snapshot; avoid recreating capture objects in Compose |

Compose migration must be screen-by-screen; a wholesale rewrite would risk MediaProjection and transport regressions.

