# Game Audio Routing

iPhone USB audio outputs are attached to the same muxed AVCapture device input as the verified display source. Preview monitoring uses `AVCaptureAudioPreviewOutput`; recording receives `AVCaptureAudioDataOutput` sample buffers. No `AVAudioEngine.inputNode` or separate microphone device is opened.

OBS Window Capture does not guarantee audio. Use a supported OBS application/system audio source and verify its meter and recording. Isolated OBS audio routing remains unverified.
