// SampleHandler.swift — CastSprint ReplayKit Broadcast Extension
// Operates under Apple's strict 50 MB memory ceiling.
import ReplayKit
import VideoToolbox

final class SampleHandler: RPBroadcastSampleHandler, VideoEncoderDelegate {
    private let encoder = VideoToolboxEncoder()
    private let transport = NetworkTransportSink()
    private var isStreaming = false
    private var currentConfigId: UInt32 = 1

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // Read configuration from shared App Group or setup info
        let host = "192.168.1.100"
        let port: UInt16 = 27183

        encoder.delegate = self
        // Balanced 1080p 60fps preset
        _ = encoder.setup(width: 1920, height: 1080, fps: 60, bitrateBps: 12_000_000)

        transport.connect(host: host, port: port) { [weak self] success in
            self?.isStreaming = success
            if !success {
                NSLog("CastSprint Extension: Failed to connect to desktop receiver")
            }
        }
    }

    override func broadcastPaused() {
        // User paused broadcast
    }

    override func broadcastResumed() {
        // User resumed broadcast
    }

    override func broadcastFinished() {
        encoder.teardown()
        transport.disconnect()
        isStreaming = false
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard isStreaming else { return }

        switch sampleBufferType {
        case .video:
            // Zero-copy encode: pass pixel buffer directly to hardware compressor
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                encoder.encode(pixelBuffer: pixelBuffer, presentationTime: pts)
            }

        case .audioApp:
            // Process internal game audio
            break

        case .audioMic:
            // Optional voice commentary
            break

        @unknown default:
            break
        }
    }

    // MARK: - VideoEncoderDelegate
    func didProduceConfigData(_ configData: Data) {
        // Dispatch VIDEO_CONFIG message
        currentConfigId += 1
    }

    func didProduceVideoFrame(ptsMicros: UInt64, isKeyframe: Bool, data: Data) {
        transport.sendVideoFrame(configId: currentConfigId, isKeyframe: isKeyframe, ptsMicros: ptsMicros, payload: data)
    }
}
