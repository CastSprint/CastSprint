// MediaPipelineContracts.swift — Unified Media Pipeline Protocol Contracts
import Foundation
import CoreMedia
import CoreVideo

public struct VideoConfigData {
    public let configId: UInt32
    public let codec: UInt8       // 1: H.264, 2: H.265
    public let width: UInt16
    public let height: UInt16
    public let frameRate: UInt16
    public let bitrate: UInt32
    public let csd: Data         // SPS/PPS Annex-B

    public init(configId: UInt32, codec: UInt8, width: UInt16, height: UInt16, frameRate: UInt16, bitrate: UInt32, csd: Data) {
        self.configId = configId
        self.codec = codec
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitrate = bitrate
        self.csd = csd
    }
}

public struct VideoFrameData {
    public let configId: UInt32
    public let flags: UInt32     // bit0: Keyframe, bit1: Discontinuity, bit2: EndOfStream
    public let ptsMicros: UInt64
    public let payload: Data

    public var isKeyframe: Bool {
        (flags & 0x01) != 0
    }

    public init(configId: UInt32, flags: UInt32, ptsMicros: UInt64, payload: Data) {
        self.configId = configId
        self.flags = flags
        self.ptsMicros = ptsMicros
        self.payload = payload
    }
}

public struct AudioConfigData {
    public let codec: UInt8      // 1: Opus, 2: AAC, 3: PCM16
    public let channels: UInt8
    public let sampleRate: UInt32
    public let csd: Data

    public init(codec: UInt8, channels: UInt8, sampleRate: UInt32, csd: Data) {
        self.codec = codec
        self.channels = channels
        self.sampleRate = sampleRate
        self.csd = csd
    }
}

public struct AudioFrameData {
    public let ptsMicros: UInt64
    public let payload: Data

    public init(ptsMicros: UInt64, payload: Data) {
        self.ptsMicros = ptsMicros
        self.payload = payload
    }
}

/// Receives compressed video bitstreams (Android / iOS LAN).
public protocol EncodedVideoInput: AnyObject {
    func onVideoConfig(_ config: VideoConfigData)
    func onVideoFrame(_ frame: VideoFrameData)
}

/// Receives native CMSampleBuffer frames (macOS iPhone USB capture).
public protocol NativeSampleBufferInput: AnyObject {
    func onVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer)
    func onAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer)
}

/// Receives audio streams.
public protocol AudioInput: AnyObject {
    func onAudioConfig(_ config: AudioConfigData)
    func onAudioFrame(_ frame: AudioFrameData)
}

/// Video presentation surface (Metal).
public protocol VideoRenderer: AnyObject {
    func renderPixelBuffer(_ pixelBuffer: CVPixelBuffer)
    func renderSampleBuffer(_ sampleBuffer: CMSampleBuffer)
    func clear()
}

/// Audio playback device.
public protocol AudioOutput: AnyObject {
    func start()
    func stop()
    func setVolume(_ volume: Float)
    func playSampleBuffer(_ sampleBuffer: CMSampleBuffer)
}

/// Disk recording sink.
public protocol RecordingSink: AnyObject {
    var isRecording: Bool { get }
    func startRecording(to url: URL, videoWidth: Int, videoHeight: Int) throws
    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer)
    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer)
    func stopRecording(completion: @escaping (URL?) -> Void)
}
