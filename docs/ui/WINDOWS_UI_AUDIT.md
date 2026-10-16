# Windows UI Audit

Framework: native Win32/C++ custom painting with D3D11 and Media Foundation. This is not WinUI.

| Area | Status | Evidence / issue | Required change |
|---|---|---|---|
| Media integration | IMPLEMENTED_UNTESTED | D3D11 renderer and decoder callbacks are wired | Preserve thread boundaries and renderer ownership |
| Navigation | WORKING / CUSTOM | Hand-painted tabs and controls | Central component metrics, keyboard focus and UI Automation |
| Theme | DARK ONLY | Compile-time RGB constants | System-aware light/dark brushes where feasible |
| DPI | NEEDS QA | Default 1280×750 window; custom pixel metrics | Per-monitor DPI calculations at 100–200% |
| Responsiveness | PARTIAL | Custom layout must handle every size manually | Minimum size, reflow/overflow, multi-monitor test matrix |
| Device work | RISK | ADB refresh is invoked during creation | Confirm all scanning/process waits remain off UI thread |
| Accessibility | MISSING | Custom-painted controls have limited native semantics | Keyboard traversal, focus rectangles, UI Automation names |

Incremental Win32 improvement is recommended. Introducing WinUI would expand runtime and packaging risk without fixing media readiness.

