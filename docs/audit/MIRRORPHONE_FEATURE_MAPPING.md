# MirrorPhone Feature Mapping

Reference revision: `d77fbc38dcf709552d1f066a000de66e0638c3fc`.

| MirrorPhone component | CastSprint equivalent | Adaptation / dependency | Test status |
|---|---|---|---|
| `DeviceDiscovery.swift` | `IPhoneUSBDisplayCaptureProvider.swift`, `USBDeviceManager.swift`, `ADBDeviceManager.swift` | `.external` + `.muxed`, CoreMediaIO activation, ADB | Build only; hardware NOT_TESTED |
| `AVCaptureMirrorSource.swift` | `IPhoneUSBCaptureSession.swift` | Native output settings, preview/data audio, quality presets | Build only; hardware NOT_TESTED |
| bounded CI display stage in `AVCaptureMirrorSource.swift` | `MetalVideoRenderer.swift` | Kept latest-frame concept but uses direct multi-target Metal; CI is diagnostic/screenshot only | Build PASS; hardware NOT_TESTED |
| `AndroidADBMirrorSource.swift` | `AndroidScreenrecordSession.swift` | ADB `exec-out screenrecord`, Annex-B parsing, VideoToolbox decode | Build PASS; hardware NOT_TESTED |
| `H264Decoder.swift` | `VideoToolboxDecoder.swift` | CastSprint receiver integration | Build PASS; stream NOT_TESTED |
| `AndroidAudioRunner.swift` | Android `AudioCaptureEngine.kt`, macOS network audio | Different CastSprint companion/LAN design retained | Android tests PASS; E2E NOT_TESTED |
| `MirrorWindowCoordinator.swift` | `MirroringCoordinator.swift` | Unified USB/LAN lifecycle and state telemetry | Build PASS |
| `MirrorWindowController.swift`, `MirrorView.swift` | `DashboardView.swift`, `OBSGameplayWindowController.swift`, `MirrorNativeDisplayView` | SwiftUI shell plus independent gameplay window | Build PASS; OBS NOT_TESTED |
| `MirrorQuality.swift` | `CaptureQualityProfile`, Android `EncoderConfig` | Automatic profile is not yet equivalent to MirrorPhone pressure adaptation | PARTIALLY_WORKING |
| `MP4Recorder.swift`, `MirrorRecording.swift` | `AVAssetWriterRecordingSink.swift` | Shared live samples, fixed canvas | Build PASS; real recording NOT_TESTED |
| Image screenshot utilities | `takeScreenshot`, renderer snapshot | PNG from latest device pixel buffer | Build PASS; real frame NOT_TESTED |
| Android input server/mappers | CastSprint source adapters only | Full MirrorPhone input and clipboard parity is not integrated | NOT_IMPLEMENTED |
| `IOSWirelessMirrorSource.swift`, `MirrorWireProtocol.swift` | CastSprint iOS app + CSP1 network receiver | CastSprint keeps its own protocol and sender | Build/source audit only |
| Multiwindow device assignments | Single coordinator plus gameplay output window | Clean output exists; independent per-device sessions do not | PARTIALLY_WORKING |

No MirrorPhone file was copied verbatim in this repair. Concepts adapted in the existing worktree are called out above. Attribution and redistribution review remain mandatory.
