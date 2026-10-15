# Android USB Audio

Status: **NOT_IMPLEMENTED**

The CastSprint app-less Android USB session currently transports H.264 video only. It does not start an Android shell-user playback-audio helper.

The authorized MirrorPhone reference contains a separate Android 11+ `app_process` helper using `REMOTE_SUBMIX`, with 48 kHz stereo signed 16-bit PCM output. Integration still requires source/license review, bundling, capability detection, clean lifecycle handling, telemetry, playback, and real-device verification. Video must remain usable when Android or an application prohibits playback capture. Microphone fallback is forbidden.
