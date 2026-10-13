// CoreAudioOutput.swift — Low-Latency CoreAudio Playback for macOS
import Foundation
import AVFoundation
import CoreMedia

public final class CoreAudioOutput: NSObject, AudioOutput {
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var isEngineRunning = false
    private var currentVolume: Float = 1.0

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
        NSLog("CastSprint: CoreAudio output engine stopped")
    }

    public func setVolume(_ volume: Float) {
        self.currentVolume = max(0.0, min(1.0, volume))
        playerNode.volume = self.currentVolume
    }

    public func playSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Feed into audio playback pipeline
        guard isEngineRunning else { return }
        // For real-time low-latency playback of linear PCM sample buffers
    }
}
