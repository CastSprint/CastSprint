# Why macOS says “Microphone”

For the selected iPhone USB capture device, AVFoundation routes digital device audio through macOS's audio-capture privacy category. macOS therefore presents a Microphone permission prompt even though CastSprint intends to consume the phone's muxed digital audio, not the Mac's physical microphone.

CastSprint 0.3.2 makes this opt-in:

1. Video capture can run without an audio request.
2. The user enables **Capture iPhone internal audio** in Settings.
3. Authorization is requested when capture starts.
4. If denied, video continues and no microphone fallback is selected.

**NOT TESTED:** prompt wording and actual muxed-audio availability on every macOS/iPhone combination.

