// SampleHandler.swift — CastSprint ReplayKit Broadcast Upload Extension
// Hardened for Apple's strict 50 MB memory ceiling.
import ReplayKit
import VideoToolbox
import CoreMedia

final class SampleHandler: RPBroadcastSampleHandler, VideoEncoderDelegate, AudioEncoderDelegate, NetworkTransportDelegate {
    private let encoder = VideoToolboxEncoder()
    private let audioEncoder = AudioToolboxEncoder()
    private let transport = NetworkTransportSink()
    private let appGroup = AppGroupBridge.shared

    private var isStreaming = false
    private var config = StreamConfiguration()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // Read configuration from shared App Group
        self.config = appGroup.loadConfiguration()

        guard !config.receiverHost.isEmpty else {
            let error = NSError(domain: "com.castsprint.ios.broadcast", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "No receiver IP configured. Please open CastSprint and select a receiver."
            ])
            finishBroadcastWithError(error)
            appGroup.updateBroadcastState("error", error: error.localizedDescription)
            return
        }

        encoder.delegate = self
        audioEncoder.delegate = self
        transport.delegate = self

        // Setup VideoToolbox hardware compressor
        let width = config.targetWidth > 0 ? config.targetWidth : 1920
        let height = config.targetHeight > 0 ? config.targetHeight : 1080
        let fps = config.targetFps > 0 ? config.targetFps : 60
        let bitrate = config.targetBitrateBps > 0 ? config.targetBitrateBps : 12_000_000

        guard encoder.setup(width: width, height: height, fps: fps, bitrateBps: bitrate) else {
            let error = NSError(domain: "com.castsprint.ios.broadcast", code: 1002, userInfo: [
                NSLocalizedDescriptionKey: "Hardware video encoder initialization failed."
            ])
            finishBroadcastWithError(error)
            appGroup.updateBroadcastState("error", error: error.localizedDescription)
            return
        }

        appGroup.updateBroadcastState("connecting")

        // Connect to Desktop Receiver over LAN
        transport.connect(
            host: config.receiverHost,
            port: config.receiverPort,
            pairingToken: config.pairingPin,
            deviceName: "iPhone",
            deviceModel: "iOS Device",
            width: UInt16(width),
            height: UInt16(height),
            fps: UInt16(fps)
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.isStreaming = true
                self.appGroup.updateBroadcastState("streaming")
                NSLog("CastSprint Extension: Successfully connected and streaming to %@", self.config.receiverHost)
            case .failure(let err):
                self.isStreaming = false
                self.finishBroadcastWithError(err)
                self.appGroup.updateBroadcastState("error", error: err.localizedDescription)
            }
        }
    }

    override func broadcastPaused() {
        appGroup.updateBroadcastState("paused")
    }

    override func broadcastResumed() {
        appGroup.updateBroadcastState("streaming")
    }

    override func broadcastFinished() {
        encoder.teardown()
        audioEncoder.teardown()
        transport.disconnect()
        isStreaming = false
        appGroup.updateBroadcastState("stopped")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard isStreaming else { return }

        switch sampleBufferType {
        case .video:
            // Zero-copy: Pass pixel buffer directly to hardware compressor on the delivery thread.
            // Never queue uncompressed CMSampleBuffers to prevent breaching the 50 MB memory ceiling.
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                encoder.encode(pixelBuffer: pixelBuffer, presentationTime: pts)
            }

        case .audioApp:
            // Game / Application Audio
            if config.isAudioEnabled {
                audioEncoder.encode(sampleBuffer: sampleBuffer)
            }

        case .audioMic:
            // CastSprint transports application audio only. Never substitute microphone input.
            break

        @unknown default:
            break
        }
    }

    // MARK: - VideoEncoderDelegate

    func didProduceConfigData(configId: UInt32, width: UInt16, height: UInt16, fps: UInt16, bitrate: UInt32, csd: Data) {
        transport.sendVideoConfig(
            configId: configId,
            width: width,
            height: height,
            fps: fps,
            bitrate: bitrate,
            csd: csd
        )
    }

    func didProduceVideoFrame(configId: UInt32, ptsMicros: UInt64, isKeyframe: Bool, data: Data) {
        transport.sendVideoFrame(
            configId: configId,
            isKeyframe: isKeyframe,
            ptsMicros: ptsMicros,
            payload: data
        )
    }

    func encoderDidEncounterError(_ error: Error) {
        NSLog("CastSprint Video Encoder Error: %@", error.localizedDescription)
    }

    // MARK: - AudioEncoderDelegate

    func didProduceAudioConfig(channels: UInt8, sampleRate: UInt32, csd: Data) {
        transport.sendAudioConfig(channels: channels, sampleRate: sampleRate, csd: csd)
    }

    func didProduceAudioFrame(ptsMicros: UInt64, data: Data) {
        transport.sendAudioFrame(ptsMicros: ptsMicros, payload: data)
    }

    func audioEncoderDidEncounterError(_ error: Error) {
        NSLog("CastSprint Audio Encoder Error: %@", error.localizedDescription)
    }

    // MARK: - NetworkTransportDelegate

    func transportDidConnect(_ transport: NetworkTransportSink, helloAck: ProtocolCodec.HelloAck) {
        appGroup.updateBroadcastState("streaming")
    }

    func transportDidDisconnect(_ transport: NetworkTransportSink, error: Error?) {
        isStreaming = false
        if let error = error {
            finishBroadcastWithError(error)
            appGroup.updateBroadcastState("error", error: error.localizedDescription)
        } else {
            appGroup.updateBroadcastState("stopped")
        }
    }

    func transportMetricsUpdated(_ transport: NetworkTransportSink, bitrateMbps: Double, rttMs: Double) {
        // Heartbeat metrics
    }
}
