// AVAssetWriterRecordingSink.swift — Native Zero-Transcode MP4 Recording Sink
import Foundation
import AVFoundation
import CoreMedia

public final class AVAssetWriterRecordingSink: NSObject, RecordingSink {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var isSessionStarted = false
    private let writerQueue = DispatchQueue(label: "com.castsprint.mac.recording", qos: .utility)

    private(set) public var isRecording = false
    public var onRecordingError: ((Error) -> Void)?

    public override init() {
        super.init()
    }

    public func startRecording(to url: URL, videoWidth: Int, videoHeight: Int) throws {
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // H.264 Video Compression Settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth > 0 ? videoWidth : 1920,
            AVVideoHeightKey: videoHeight > 0 ? videoHeight : 1080,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 14_000_000, // 14 Mbps high-quality gaming
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        if writer.canAdd(vInput) {
            writer.add(vInput)
            self.videoInput = vInput
        }

        // AAC Audio Settings
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]

        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true
        if writer.canAdd(aInput) {
            writer.add(aInput)
            self.audioInput = aInput
        }

        guard writer.startWriting() else {
            let err = writer.error ?? NSError(domain: "CastSprint", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start asset writer"])
            throw err
        }

        self.assetWriter = writer
        self.outputURL = url
        self.isRecording = true
        self.isSessionStarted = false
        NSLog("CastSprint: MP4 recording started to %@", url.path)
    }

    public func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }

        writerQueue.async { [weak self] in
            guard let self = self, self.isRecording,
                  let writer = self.assetWriter,
                  let vInput = self.videoInput else { return }

            if writer.status == .failed {
                if let err = writer.error {
                    self.isRecording = false
                    self.onRecordingError?(err)
                }
                return
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !self.isSessionStarted {
                writer.startSession(atSourceTime: pts)
                self.isSessionStarted = true
            }

            if vInput.isReadyForMoreMediaData {
                vInput.append(sampleBuffer)
            }
        }
    }

    public func appendPixelBuffer(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard isRecording else { return }

        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDesc)
        guard let formatDesc = formatDesc else { return }

        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        if let sb = sampleBuffer {
            appendVideoSampleBuffer(sb)
        }
    }

    public func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }

        writerQueue.async { [weak self] in
            guard let self = self, self.isRecording,
                  self.isSessionStarted,
                  let writer = self.assetWriter,
                  let aInput = self.audioInput else { return }

            if writer.status == .failed {
                return
            }

            if aInput.isReadyForMoreMediaData {
                aInput.append(sampleBuffer)
            }
        }
    }

    public func stopRecording(completion: @escaping (URL?) -> Void) {
        writerQueue.async { [weak self] in
            guard let self = self, self.isRecording, let writer = self.assetWriter else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            self.isRecording = false
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()

            writer.finishWriting {
                let finalURL = self.outputURL
                self.assetWriter = nil
                self.videoInput = nil
                self.audioInput = nil
                NSLog("CastSprint: Finalized MP4 recording: %@", finalURL?.path ?? "unknown")
                DispatchQueue.main.async {
                    completion(finalURL)
                }
            }
        }
    }
}
