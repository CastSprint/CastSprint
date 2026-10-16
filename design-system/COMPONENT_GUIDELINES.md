# Component Guidelines

## Shared behavior

- `CastSprintLogo`: official vector/app asset, fixed proportions, accessible name only when not adjacent to wordmark.
- `DeviceCard`: stable device identity, platform + transport, authorization, video/audio capability, one primary Connect/Disconnect action.
- `ConnectionStatus`: icon, human label, optional detail; never color-only.
- `ConnectionWizard`: step title, concise explanation, current progress, Back/Cancel, one primary action, recovery path.
- `QualitySelector`: plain-language preset first; technical details secondary; selected state announced.
- `AudioMeter`: labelled channel/source, peak and mute state; decorative bars hidden from accessibility APIs.
- `VideoStats`: capture, received, rendered, dropped, format; update no faster than twice per second in UI.
- `EmptyState`: what is missing + one next action; no indefinite “searching” copy when scanning stopped.
- `ErrorState`: cause where known, user-safe action, diagnostics link/copy control.
- `StreamingToolbar`: one row on wide layouts, grouped overflow on compact layouts, never overlays telemetry or video.
- `RecordingControls`: distinguish Record, Recording, Stopping, and Saved; include elapsed time and destination.
- `ThemeSelector`: System, Light, Dark; System default.
- `SettingsSection`: native grouped structure, clear descriptions, controls persist only when successfully applied.
- `PermissionExplanation`: explain why, which source, privacy boundary, and how to change later.

## Button hierarchy

One primary action per region. Secondary buttons use bordered/tonal styling. Destructive actions require a destructive role and remain visually distinct. Disabled controls explain the unmet prerequisite nearby.

## Status cards

Telemetry must reflect the last measured interval. If capture FPS is positive and rendered FPS remains zero, show `Renderer error`, not `Streaming`.

