# Native Media Pipeline

## macOS iPhone USB

`CoreMediaIO activation → AVFoundation .external/.muxed device → AVCaptureSession → CMSampleBuffer → CVPixelBuffer → CVMetalTextureCache → CAMetalLayer`.

Capture and presentation are separate facts. `PipelineTelemetry` tracks source samples and metadata independently from texture creation, command encoding, command commit, GPU completion and presented FPS. `MirroringCoordinator` reports rendering only after successful GPU completion.

`AVCaptureAudioPreviewOutput` provides system monitoring where the muxed device exposes audio. `AVCaptureAudioDataOutput` feeds recording/processing. A denial or unavailable audio port must not be reported as active audio.

## macOS Android USB

`ADB exec-out screenrecord → Annex-B H.264 parser → VideoToolboxDecoder → CVPixelBuffer → shared Metal renderer`. The app-less route does not require the CastSprint APK. Android internal audio support on this route is not hardware-verified.

## LAN

The Android/iOS companions encode on-device and send CastSprint protocol packets to the native receiver. VideoToolbox produces CVPixelBuffers for the same renderer; audio is scheduled separately. Transport, decode and render queues must stay bounded.
