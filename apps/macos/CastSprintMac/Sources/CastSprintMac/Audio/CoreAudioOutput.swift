// CoreAudioOutput.swift — Low-Latency CoreAudio Playback for macOS
import Foundation
import AVFoundation
import CoreMedia

public final class CoreAudioOutput: NSObject, AudioOutput {
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var isEngineRunning = false
    private var currentVolume: Float = 1.0
    private var isMuted: Bool = false

    private(set) public var audioSampleRate: Double = 48000.0
    private(set) public var audioChannelCount: UInt32 = 2
    private(set) public var hasReceivedAudio: Bool = false

    public override init() {
        self.audioEngine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        super.init()

        audioEngine.attach(playerNode)
        let mainMixer = audioEngine.mainMixerNode
        audioEngine.connect(playerNode, to: mainMixer, format: nil)
    }

    public func start() {
        guard !isEngineRunning else { return }
        do {
            try audioEngine.start()
            playerNode.play()
            isEngineRunning = true
            NSLog("CastSprint: CoreAudio output engine started")
        } catch {
            NSLog("CastSprint: Failed to start CoreAudio engine: %@", error.localizedDescription)
        }
    }

    public func stop() {
        guard isEngineRunning else { return }
        playerNode.stop()
        audioEngine.stop()
        isEngineRunning = false
        hasReceivedAudio = false
        NSLog("CastSprint: CoreAudio output engine stopped")
    }

    public func setVolume(_ volume: Float) {
        self.currentVolume = max(0.0, min(1.0, volume))
        if !isMuted {
            playerNode.volume = self.currentVolume
        }
    }

    public func setMuted(_ muted: Bool) {
        self.isMuted = muted
        playerNode.volume = muted ? 0.0 : self.currentVolume
    }

    public func playSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isEngineRunning, !isMuted else { return }

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }

        self.audioSampleRate = asbd.pointee.mSampleRate
        self.audioChannelCount = asbd.pointee.mChannelsPerFrame
        self.hasReceivedAudio = true

        // Extract PCM block buffer for playback
        var numSamples: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &numSamples)

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var lengthAtOffset: size_t = 0
        var totalLength: size_t = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let ptr = dataPointer, totalLength > 0 else { return }

        // Schedule buffer with player node if format matches
        if let audioFormat = AVAudioFormat(streamDescription: asbd) {
            let frameCount = UInt32(totalLength) / asbd.pointee.mBytesPerFrame
            if let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) {
                pcmBuffer.frameLength = frameCount
                if let channelData = pcmBuffer.audioBufferList.pointee.mBuffers.mData {
                    memcpy(channelData, ptr, totalLength)
                    playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
                }
            }
        }
    }

    public func playPCMData(_ data: Data, sampleRate: Double = 48000.0, channels: UInt32 = 2) {
        guard isEngineRunning, !isMuted, !data.isEmpty else { return }

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: channels * 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: channels * 2,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        guard let audioFormat = AVAudioFormat(streamDescription: &asbd) else { return }
        let bytesPerFrame = asbd.mBytesPerFrame
        let frameCount = UInt32(data.count) / bytesPerFrame
        guard frameCount > 0 else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress,
               let channelData = pcmBuffer.audioBufferList.pointee.mBuffers.mData {
                memcpy(channelData, baseAddress, data.count)
                playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
            }
        }
        self.hasReceivedAudio = true
    }
}

