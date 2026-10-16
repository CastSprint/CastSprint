# Accessibility Standard

Target WCAG 2.2 AA where applicable and native platform accessibility guidance.

- Normal text contrast: 4.5:1 minimum; large text and meaningful non-text UI: 3:1 minimum.
- Visible focus on every keyboard control. Sticky UI must not fully obscure focus.
- iOS targets: 44×44 pt. Android: 48×48 dp. Desktop/web: at least 40×40 where practical.
- Support keyboard operation for navigation, dialogs, selectors, recording, and connect/disconnect.
- VoiceOver/TalkBack names describe outcome, not glyph shape. Announce selected, expanded, disabled, busy, and error states.
- Dynamic Type/font scaling must wrap or reflow essential labels; do not truncate device names or errors without a full-detail path.
- Respect Reduce Motion and increased contrast. Do not make success/error dependent only on color.
- Live telemetry is not an assertive live region; critical disconnect/error announcements are polite and deduplicated.
- QR/manual pairing always provides a non-camera/manual alternative.
- Authentication fields allow paste and password managers where relevant.

## Verification checklist

Keyboard-only pass, screen-reader smoke pass, 200% web zoom, maximum mobile text size, light/dark contrast, reduced motion, portrait/landscape, and minimum-window testing are required before `VERIFIED_WORKING`.

