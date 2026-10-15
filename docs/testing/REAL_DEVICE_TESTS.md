# Real Device Tests — Current Gate

Audit date: 2026-10-15. No phone was visible through `xcrun devicectl` or `adb devices -l`. Consequently, every physical result below is `NOT_TESTED` in the current run.

| Test | Status |
|---|---|
| iPhone 15 USB Home Screen/video | NOT_TESTED |
| iPhone 15 USB internal audio | NOT_TESTED |
| iPhone rotation/reconnect | NOT_TESTED |
| Android USB display/audio | NOT_TESTED |
| Android Wi-Fi display/audio/reconnect | NOT_TESTED |
| iPhone Wi-Fi display/audio/lifecycle | NOT_TESTED |
| OBS video/audio recording | NOT_TESTED |
| Streamlabs video/audio recording | NOT_TESTED |
| 10/30-minute stability | NOT_TESTED |
| Glass-to-glass median/p95 latency | NOT_TESTED |

Next iPhone run: connect and unlock the phone, trust the Mac, close competing capture apps, start CastSprint, show the Home Screen, arm the one-frame diagnostic, inspect PNG/metadata, then verify both visible windows and audio. A PASS requires an observed moving real display, not FPS counters.
