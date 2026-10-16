# Interaction Patterns

## USB connection

1. Connect phone.
2. Detect device without blocking UI.
3. Show authorization/unlock requirement.
4. Select screen-mirroring route.
5. Start capture.
6. Change state to Rendering only after a real frame is presented.

## Wi-Fi connection

1. Discover on the same reachable network or allow manual address.
2. Select stable device identity.
3. Authenticate pairing.
4. Request platform screen-capture consent.
5. Negotiate media.
6. Render real frames, then show Streaming.

## Recovery

Timeouts retain the chosen device and offer Retry. Permission denial links to platform-specific settings/instructions. Disconnect preserves user preferences but clears stale session state. Active sessions never auto-switch devices.

## Navigation

Changing tabs preserves capture. Closing the OBS window detaches only that render target. Settings that require restart say so before applying. Modal focus enters at the title/first control and returns to its trigger.

## Creator workflow

`Open Gameplay Window`, orientation, canvas, fit/fill/crop, recording, screenshot, monitoring, and diagnostics are grouped by outcome. The clean window contains pixels only; no CastSprint chrome.

