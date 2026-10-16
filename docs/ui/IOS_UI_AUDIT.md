# iOS UI Audit

Framework: SwiftUI with ReplayKit/extension capture, Bonjour browser, QR scanner, and network transport.

| Area | Status | Evidence / issue | Required change |
|---|---|---|---|
| Navigation | WORKING / DENSE | Five tabs on phone | Four-or-fewer primary destinations; move About into Settings |
| Discovery | WORKING / UNVERIFIED | Bonjour list and manual/QR pairing paths exist | Stable selection, retry and wrong-network guidance |
| Status truth | BROKEN | Header displays `READY` while merely idle/searchable | Use Available/Searching/Authenticated/Streaming truth model |
| Theme | BROKEN | Hard-coded dark background and white text | System color scheme and semantic tokens |
| Type | INACCESSIBLE | Fixed system font sizes throughout | Dynamic Type styles and adaptive card flow |
| Capture | IMPLEMENTED_UNTESTED | Public ReplayKit path and extension exist | Preserve; clarify Apple broadcast lifecycle |
| Accessibility | PARTIAL | Native SwiftUI controls present | VoiceOver labels/state, large-text and safe-area verification |

