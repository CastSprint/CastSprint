// AudioToolboxEncoder.swift — iOS Hardware-Accelerated AAC-LC Audio Compression
import Foundation
import CoreMedia
import AudioToolbox
import AVFoundation

public protocol AudioEncoderDelegate: AnyObject {
    func didProduceAudioConfig(channels: UInt8, sampleRate: UInt32, csd: Data)
    func didProduceAudioFrame(ptsMicros: UInt64, data: Data)
    func audioEncoderDidEncounterError(_ error: Error)
}

public final class AudioToolboxEncoder {
    public weak var delegate: AudioEncoderDelegate?

    private var audioConverter: AudioConverterRef?
    private var inputFormat: AudioStreamBasicDescription?
    private var outputFormat: AudioStreamBasicDescription?

    private var hasDispatchedConfig: Bool = false
    private let aacPacketSize: UInt32 = 1024
    private var pcmBuffer = Data()
    private let audioQueue = DispatchQueue(label: "com.castsprint.ios.audio", qos: .userInteractive)

    public init() {}

    deinit {
        teardown()
    }

    public func teardown() {
        if let converter = audioConverter {
            AudioConverterDispose(converter)
            audioConverter = nil
        }
        hasDispatchedConfig = false
        pcmBuffer.removeAll()
    }

    public func encode(sampleBuffer: CMSampleBuffer) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }

            guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
                return
            }

            let inAsbd = asbdPtr.pointee

            if self.audioConverter == nil || self.inputFormat?.mSampleRate != inAsbd.mSampleRate {
                if !self.setupConverter(inputAsbd: inAsbd) {
                    return
                }
            }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
            var lengthAtOffset: size_t = 0
            var totalLength: size_t = 0
            var dataPointer: UnsafeMutablePointer<Int8>?

            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )

            guard status == noErr, let ptr = dataPointer, totalLength > 0 else { return }

            let ptsSeconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            let ptsMicros = UInt64(ptsSeconds * 1_000_000.0)

            self.processPcmBytes(UnsafePointer(ptr), count: totalLength, ptsMicros: ptsMicros)
        }
    }

    private func setupConverter(inputAsbd: AudioStreamBasicDescription) -> Bool {
        teardown()
        self.inputFormat = inputAsbd

        // Target: AAC-LC, matching sample rate, 2 channels
        var outAsbd = AudioStreamBasicDescription()
        outAsbd.mFormatID = kAudioFormatMPEG4AAC
        outAsbd.mFormatFlags = UInt32(MPEG4ObjectID.AAC_LC.rawValue)
        outAsbd.mSampleRate = inputAsbd.mSampleRate > 0 ? inputAsbd.mSampleRate : 48000.0
        outAsbd.mChannelsPerFrame = min(2, max(1, inputAsbd.mChannelsPerFrame))
        outAsbd.mFramesPerPacket = 1024
        outAsbd.mBytesPerPacket = 0
        outAsbd.mBytesPerFrame = 0
        outAsbd.mBitsPerChannel = 0
        self.outputFormat = outAsbd

        var inFormat = inputAsbd
        var converter: AudioConverterRef?
        let status = AudioConverterNew(&inFormat, &outAsbd, &converter)

        guard status == noErr, let converter = converter else {
            NSLog("CastSprint: AudioConverterNew failed with %d", status)
            return false
        }

        // Set AAC Bitrate to 128 kbps
        var bitrate: UInt32 = 128_000
        AudioConverterSetProperty(
            converter,
            kAudioConverterEncodeBitRate,
            UInt32(MemoryLayout<UInt32>.size),
            &bitrate
        )

        self.audioConverter = converter

        // Generate AudioSpecificConfig (CSD)
        // Profile (5 bits: 2 for AAC-LC) | Sample Rate Index (4 bits) | Channels (4 bits)
        let csd = generateAudioSpecificConfig(sampleRate: outAsbd.mSampleRate, channels: UInt8(outAsbd.mChannelsPerFrame))
        self.delegate?.didProduceAudioConfig(
            channels: UInt8(outAsbd.mChannelsPerFrame),
            sampleRate: UInt32(outAsbd.mSampleRate),
            csd: csd
        )
        self.hasDispatchedConfig = true
        return true
    }

    private func processPcmBytes(_ bytes: UnsafePointer<Int8>, count: Int, ptsMicros: UInt64) {
        guard let converter = audioConverter, let inAsbd = inputFormat, let outAsbd = outputFormat else { return }

        // Max AAC output packet size ~ 1536 bytes
        var outBuffer = [UInt8](repeating: 0, count: 2048)
        outBuffer.withUnsafeMutableBytes { (rawBufPtr: UnsafeMutableRawBufferPointer) in
            var outBufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: outAsbd.mChannelsPerFrame,
                    mDataByteSize: UInt32(rawBufPtr.count),
                    mData: rawBufPtr.baseAddress
                )
            )

            var ioOutputDataPacketSize: UInt32 = 1

            struct ConverterContext {
                var data: UnsafePointer<Int8>
                var size: UInt32
                var asbd: AudioStreamBasicDescription
            }

            var context = ConverterContext(data: bytes, size: UInt32(count), asbd: inAsbd)

            let inputCallback: AudioConverterComplexInputDataProc = { _, ioNumberDataPackets, ioData, _, inUserData in
                guard let inUserData = inUserData else { return -1 }
                let ctx = inUserData.assumingMemoryBound(to: ConverterContext.self)

                if ctx.pointee.size == 0 {
                    ioNumberDataPackets.pointee = 0
                    return noErr
                }

                let bytesPerPacket = ctx.pointee.asbd.mBytesPerPacket > 0 ? ctx.pointee.asbd.mBytesPerPacket : 4
                let maxPackets = ctx.pointee.size / bytesPerPacket
                let packetsToProvide = min(ioNumberDataPackets.pointee, maxPackets)

                let bytesToProvide = packetsToProvide * bytesPerPacket
                ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: ctx.pointee.data)
                ioData.pointee.mBuffers.mDataByteSize = bytesToProvide
                ioData.pointee.mBuffers.mNumberChannels = ctx.pointee.asbd.mChannelsPerFrame

                ctx.pointee.data = ctx.pointee.data.advanced(by: Int(bytesToProvide))
                ctx.pointee.size -= bytesToProvide
                ioNumberDataPackets.pointee = packetsToProvide

                return noErr
            }

            let status = AudioConverterFillComplexBuffer(
                converter,
                inputCallback,
                &context,
                &ioOutputDataPacketSize,
                &outBufferList,
                nil
            )

            if status == noErr && ioOutputDataPacketSize > 0 {
                let encodedSize = Int(outBufferList.mBuffers.mDataByteSize)
                if encodedSize > 0, let basePtr = rawBufPtr.baseAddress {
                    let packetData = Data(bytes: basePtr, count: encodedSize)
                    self.delegate?.didProduceAudioFrame(ptsMicros: ptsMicros, data: packetData)
                }
            }
        }
    }

    private func generateAudioSpecificConfig(sampleRate: Float64, channels: UInt8) -> Data {
        let sampleRates: [Float64] = [
            96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350
        ]
        var rateIndex: UInt8 = 4 // Default 44100
        for (idx, rate) in sampleRates.enumerated() {
            if abs(rate - sampleRate) < 1.0 {
                rateIndex = UInt8(idx)
                break
            }
        }

        // Profile: AAC-LC = 2
        let profile: UInt8 = 2
        let byte1 = (profile << 3) | ((rateIndex >> 1) & 0x07)
        let byte2 = ((rateIndex & 0x01) << 7) | ((channels & 0x0F) << 3)

        return Data([byte1, byte2])
    }
}
