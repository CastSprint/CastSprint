# Cross-platform codec compatibility

| Endpoint | Encode | Decode/playback | Status |
|---|---|---|---|
| Android | AAC via MediaCodec / playback capture | n/a | BUILD_ONLY |
| iOS | AAC via AudioToolbox from `.audioApp` | n/a | IMPLEMENTED_UNTESTED |
| macOS | n/a | AAC via `AVAudioConverter`; PCM via bounded scheduling | IMPLEMENTED_UNTESTED |
| Windows | n/a | Media Foundation/WASAPI path present | PARTIAL |
| Linux | n/a | no codec or output backend | MISSING |

The protocol AUDIO_CONFIG must arrive before AUDIO_FRAME. Codec 1 is Opus, codec 2 is AAC, and codec 3 is PCM16; unsupported codecs fail closed. macOS now consumes AAC AudioSpecificConfig as the converter magic cookie instead of sending compressed bytes to a PCM node.

Microphone policy: iOS `.audioMic` is discarded, the broadcast picker hides its microphone control, and the app no longer declares microphone usage. Android must continue to use `AudioPlaybackCapture`, never `MIC`.

Hardware evidence for audible LAN audio and OBS A/V sync remains BLOCKED/UNTESTED.
