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

    private(set) public var isRecording = false

    public override init() {
        super.init()
    }

    public func startRecording(to url: URL, videoWidth: Int, videoHeight: Int) throws {
        // Remove existing file if present
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // Pass-through video writer input
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
        vInput.expectsMediaDataInRealTime = true
        if writer.canAdd(vInput) {
            writer.add(vInput)
        }

        // Pass-through audio writer input
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        aInput.expectsMediaDataInRealTime = true
        if writer.canAdd(aInput) {
            writer.add(aInput)
        }

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "CastSprint", code: -1, userInfo: nil)
        }

        self.assetWriter = writer
        self.videoInput = vInput
        self.audioInput = aInput
        self.outputURL = url
        self.isRecording = true
        self.isSessionStarted = false
        NSLog("CastSprint: Started MP4 recording to %@", url.path)
    }

    public func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, let writer = assetWriter, let vInput = videoInput else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !isSessionStarted {
            writer.startSession(atSourceTime: pts)
            isSessionStarted = true
        }

        if vInput.isReadyForMoreMediaData {
            vInput.append(sampleBuffer)
        }
    }

    public func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, isSessionStarted, let aInput = audioInput else { return }

        if aInput.isReadyForMoreMediaData {
            aInput.append(sampleBuffer)
        }
    }

    public func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording, let writer = assetWriter else {
            completion(nil)
            return
        }

        self.isRecording = false
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        writer.finishWriting { [weak self] in
            let finalURL = self?.outputURL
            self?.assetWriter = nil
            self?.videoInput = nil
            self?.audioInput = nil
            NSLog("CastSprint: Finalized MP4 recording")
            DispatchQueue.main.async {
                completion(finalURL)
            }
        }
    }
}
