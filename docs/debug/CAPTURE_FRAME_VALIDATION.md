# Capture Frame Validation

The installed 0.2.1 build exposes an explicit **Settings → Capture Next Source Frame** action. It arms exactly one export from the next real `CVPixelBuffer` and writes:

- `~/Library/Logs/CastSprint/Diagnostics/source-frame-<timestamp>.png`
- a matching `.txt` containing capture time, width, height, FourCC and plane count.

This action is disabled until a mirroring session starts. It never continuously records private screen content.

Current result (2026-10-15): **NOT_TESTED**. No iPhone was enumerated after the installed app launched, so no source frame could be requested. The next run must show the unlocked iPhone Home Screen, trigger one export, and visually inspect the PNG before the renderer is declared fixed.
