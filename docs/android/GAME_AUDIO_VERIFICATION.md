# Android game audio verification

Status: **BUILD_ONLY**.

The Android sender uses AudioPlaybackCapture and AAC; macOS now negotiates AUDIO_CONFIG and decodes AAC with AVAudioConverter. USB Gaming starts the same audio-capable receiver. No Android phone was connected during this run, so sample receipt, audible output, restrictions imposed by a real game, underruns and OBS recording are unverified.

Microphone fallback is prohibited. If a game disallows playback capture, video must continue and the UI must report audio unavailable.
