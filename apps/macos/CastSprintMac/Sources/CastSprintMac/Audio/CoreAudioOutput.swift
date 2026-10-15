// CoreAudioOutput.swift — Low-Latency CoreAudio Playback for macOS
import Foundation
import AVFoundation
import CoreMedia
import CCastSprintProtocol


public final class CoreAudioOutput: NSObject, AudioOutput {
    static let maximumScheduledBuffers = 12
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var engineFormat: AVAudioFormat?
    private var currentConverter: AVAudioConverter?
    private var isEngineRunning = false
    private var currentVolume: Float = 1.0
    private var isMuted: Bool = false
    private let audioQueue = DispatchQueue(label: "com.castsprint.mac.audio.output", qos: .userInteractive)
    private let bufferLock = NSLock()
    private var scheduledBufferCount = 0

    private(set) public var audioSampleRate: Double = 48000.0
    private(set) public var audioChannelCount: UInt32 = 2
    private(set) public var hasReceivedAudio: Bool = false

    public override init() {
        self.audioEngine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        super.init()

        setupEngine()
        registerEngineObservers()
    }

    private func setupEngine() {
        audioEngine.attach(playerNode)
        let mainMixer = audioEngine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        self.engineFormat = format
        self.audioSampleRate = format.sampleRate
        self.audioChannelCount = format.channelCount

        audioEngine.connect(playerNode, to: mainMixer, format: format)
    }

    private func registerEngineObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
    }

    @objc private func handleEngineConfigurationChange(notification: Notification) {
        audioQueue.async { [weak self] in
            guard let self = self, self.isEngineRunning else { return }
            do {
                try self.audioEngine.start()
                self.playerNode.play()
                NSLog("CastSprint: CoreAudio engine recovered from configuration change")
            } catch {
                NSLog("CastSprint: Warning — Failed to recover CoreAudio engine: %@", error.localizedDescription)
            }
        }
    }

    public func start() {
        audioQueue.sync {
            guard !isEngineRunning else { return }
            do {
                if !audioEngine.isRunning {
                    try audioEngine.start()
                }
                playerNode.play()
                isEngineRunning = true
                NSLog("CastSprint: CoreAudio output engine started (format: %@)", String(describing: engineFormat))
            } catch {
                NSLog("CastSprint: Failed to start CoreAudio engine: %@", error.localizedDescription)
            }
        }
    }

    public func stop() {
        audioQueue.sync {
            guard isEngineRunning else { return }
            playerNode.stop()
            audioEngine.stop()
            isEngineRunning = false
            hasReceivedAudio = false
            currentConverter = nil
            bufferLock.lock()
            scheduledBufferCount = 0
            bufferLock.unlock()
            NSLog("CastSprint: CoreAudio output engine stopped")
        }
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
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
              let inFormat = AVAudioFormat(streamDescription: asbd) else {
            return
        }

        guard let engineFormat = self.engineFormat else { return }

        // Setup format converter if needed
        if currentConverter == nil || currentConverter?.inputFormat != inFormat {
            currentConverter = AVAudioConverter(from: inFormat, to: engineFormat)
            if currentConverter == nil {
                NSLog("CastSprint: Warning — Cannot create audio converter from %@ to %@", inFormat, engineFormat)
                return
            }
        }
        guard let conv = currentConverter else { return }

        // Extract AudioBufferList from sampleBuffer
        var blockBuffer: CMBlockBuffer?
        var bufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return }

        guard let inPCM = AVAudioPCMBuffer(pcmFormat: inFormat, bufferListNoCopy: &bufferList, deallocator: nil) else {
            return
        }

        let outCapacity = AVAudioFrameCount(Double(numSamples) * (engineFormat.sampleRate / inFormat.sampleRate)) + 128
        guard let outPCM = AVAudioPCMBuffer(pcmFormat: engineFormat, frameCapacity: outCapacity) else { return }

        var convError: NSError?
        let convStatus = conv.convert(to: outPCM, error: &convError) { _, outStatus in
            outStatus.pointee = .haveData
            return inPCM
        }

        if (convStatus == .haveData || convStatus == .inputRanDry) && outPCM.frameLength > 0 {
            guard isEngineRunning, audioEngine.isRunning, playerNode.isPlaying else { return }
            let playerFormat = playerNode.outputFormat(forBus: 0)
            guard outPCM.format.sampleRate == playerFormat.sampleRate &&
                  outPCM.format.channelCount == playerFormat.channelCount else {
                return
            }

            guard reserveScheduledBuffer() else { return }
            var errBuf = [CChar](repeating: 0, count: 256)
            let scheduled = csp_safe_audio_schedule({ [weak self] in
                self?.playerNode.scheduleBuffer(outPCM) { [weak self] in
                    self?.releaseScheduledBuffer()
                }
            }, &errBuf, errBuf.count)

            if scheduled {
                self.hasReceivedAudio = true
            } else {
                releaseScheduledBuffer()
                let errMsg = String(cString: errBuf)
                NSLog("CastSprint: CoreAudio safely caught scheduling error: %@", errMsg)
            }
        }
    }


    public func playPCMData(_ data: Data, sampleRate: Double = 48000.0, channels: UInt32 = 2) {
        guard isEngineRunning, !isMuted, !data.isEmpty else { return }
        guard let engineFormat = self.engineFormat else { return }

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

        guard let inFormat = AVAudioFormat(streamDescription: &asbd) else { return }
        let bytesPerFrame = asbd.mBytesPerFrame
        let frameCount = UInt32(data.count) / bytesPerFrame
        guard frameCount > 0 else { return }

        guard let inPCM = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frameCount) else { return }
        inPCM.frameLength = frameCount

        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress,
               let channelData = inPCM.audioBufferList.pointee.mBuffers.mData {
                memcpy(channelData, baseAddress, data.count)
            }
        }

        if inFormat == engineFormat {
            guard isEngineRunning, audioEngine.isRunning, playerNode.isPlaying else { return }
            guard reserveScheduledBuffer() else { return }
            var errBuf = [CChar](repeating: 0, count: 256)
            let scheduled = csp_safe_audio_schedule({ [weak self] in
                self?.playerNode.scheduleBuffer(inPCM) { [weak self] in
                    self?.releaseScheduledBuffer()
                }
            }, &errBuf, errBuf.count)
            if scheduled {
                self.hasReceivedAudio = true
            } else {
                releaseScheduledBuffer()
            }
            return
        }

        let converter = AVAudioConverter(from: inFormat, to: engineFormat)
        let outCapacity = AVAudioFrameCount(Double(frameCount) * (engineFormat.sampleRate / sampleRate)) + 64
        guard let outPCM = AVAudioPCMBuffer(pcmFormat: engineFormat, frameCapacity: outCapacity) else { return }

        var convError: NSError?
        _ = converter?.convert(to: outPCM, error: &convError) { _, outStatus in
            outStatus.pointee = .haveData
            return inPCM
        }

        if outPCM.frameLength > 0 && outPCM.format == playerNode.outputFormat(forBus: 0) {
            guard isEngineRunning, audioEngine.isRunning, playerNode.isPlaying else { return }
            guard reserveScheduledBuffer() else { return }
            var errBuf = [CChar](repeating: 0, count: 256)
            let scheduled = csp_safe_audio_schedule({ [weak self] in
                self?.playerNode.scheduleBuffer(outPCM) { [weak self] in
                    self?.releaseScheduledBuffer()
                }
            }, &errBuf, errBuf.count)
            if scheduled {
                self.hasReceivedAudio = true
            } else {
                releaseScheduledBuffer()
            }
        }
    }

    private func reserveScheduledBuffer() -> Bool {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard scheduledBufferCount < Self.maximumScheduledBuffers else { return false }
        scheduledBufferCount += 1
        return true
    }

    private func releaseScheduledBuffer() {
        bufferLock.lock()
        scheduledBufferCount = max(0, scheduledBufferCount - 1)
        bufferLock.unlock()
    }


    deinit {
        NotificationCenter.default.removeObserver(self)
        if audioEngine.isRunning {
            playerNode.stop()
            audioEngine.stop()
        }
    }
}

