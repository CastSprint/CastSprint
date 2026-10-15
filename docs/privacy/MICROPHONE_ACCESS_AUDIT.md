# Microphone Access Audit

Status: **IMPLEMENTED_UNTESTED**

CastSprint does not access `AVAudioEngine.inputNode` and does not create a separate built-in, external, Continuity Camera, or phone-microphone input. The iPhone path creates one `AVCaptureDeviceInput` from the validated screen/muxed device, then attaches audio preview/data outputs to that session.

macOS categorizes `AVCaptureDevice` audio authorization as microphone access, so Mic Mode/privacy UI may appear while authorized digital USB game audio is active. This indicator is not suppressed. The previous launch-time audio permission request was removed; authorization is now requested only when starting iPhone mirroring. If denied, video starts without audio.

Runtime diagnostics retain device name, device type, transport value, and input media-port types. Physical controlled-sound verification remains required before declaring that every driver exposes internal audio rather than a microphone channel.
