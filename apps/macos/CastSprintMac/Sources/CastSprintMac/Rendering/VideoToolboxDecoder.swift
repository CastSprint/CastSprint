// VideoToolboxDecoder.swift — Hardware-Accelerated VideoToolbox H.264/HEVC Decompressor
import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

public protocol VideoDecoderDelegate: AnyObject {
    func didDecompressPixelBuffer(_ pixelBuffer: CVPixelBuffer, ptsMicros: UInt64)
    func didEncounterDecoderError(_ error: Error)
}

public final class VideoToolboxDecoder {
    public weak var delegate: VideoDecoderDelegate?

    public private(set) var decompressionSession: VTDecompressionSession?
    public private(set) var formatDescription: CMVideoFormatDescription?


    private var hasReceivedKeyframe: Bool = false
    private var activeConfigId: UInt32 = 0

    public private(set) var decodedWidth: Int = 0
    public private(set) var decodedHeight: Int = 0
    public private(set) var totalFramesDecoded: UInt64 = 0
    public private(set) var totalFramesDropped: UInt64 = 0

    public init() {}

    deinit {
        teardown()
    }

    public func teardown() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        formatDescription = nil
        hasReceivedKeyframe = false
    }

    /// Configures the H.264 hardware decompressor from Annex-B SPS and PPS NALUs
    public func configureH264(configId: UInt32, csdAnnexB: Data, width: Int, height: Int) -> Bool {
        teardown()
        self.activeConfigId = configId

        // 1. Parse Annex-B SPS and PPS parameter sets
        let parameterSets = extractParameterSets(from: csdAnnexB)
        guard let sps = parameterSets.first(where: { isSpsNALU($0) }),
              let pps = parameterSets.first(where: { isPpsNALU($0) }) else {
            NSLog("CastSprint Decoder: Failed to extract SPS/PPS from Annex-B CSD (found %d NALUs)", parameterSets.count)
            return false
        }

        var formatDesc: CMFormatDescription?
        let spsPointer = [UInt8](sps)
        let ppsPointer = [UInt8](pps)

        let status = spsPointer.withUnsafeBufferPointer { spsBuf in
            ppsPointer.withUnsafeBufferPointer { ppsBuf in
                var pointers: [UnsafePointer<UInt8>] = [spsBuf.baseAddress!, ppsBuf.baseAddress!]
                var sizes: [Int] = [spsBuf.count, ppsBuf.count]

                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &pointers,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDesc
                )
            }
        }

        guard status == noErr, let formatDesc = formatDesc else {
            NSLog("CastSprint Decoder: CMVideoFormatDescriptionCreateFromH264ParameterSets failed with OSStatus %d", status)
            return false
        }
        self.formatDescription = formatDesc

        // The encoded SPS is authoritative for raw Android screenrecord streams.
        // Callers often do not know the device orientation or native size before
        // the first parameter set arrives, so never force an unrelated 1080p
        // allocation onto VideoToolbox.
        let encodedDimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
        let outputWidth = width > 0 ? width : Int(encodedDimensions.width)
        let outputHeight = height > 0 ? height : Int(encodedDimensions.height)
        self.decodedWidth = outputWidth
        self.decodedHeight = outputHeight

        // 2. Create VTDecompressionSession with zero-copy Metal compatibility
        let destinationPixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: outputWidth,
            kCVPixelBufferHeightKey as String: outputHeight
        ]

        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { outputCallbackRefCon, _, status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration in
                guard let refCon = outputCallbackRefCon else { return }
                let decoder = Unmanaged<VideoToolboxDecoder>.fromOpaque(refCon).takeUnretainedValue()
                decoder.handleDecompressedFrame(status: status, pixelBuffer: imageBuffer, pts: presentationTimeStamp)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var session: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: nil, // Automatic hardware acceleration selection
            imageBufferAttributes: destinationPixelBufferAttributes as CFDictionary,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &session
        )

        guard sessionStatus == noErr, let session = session else {
            NSLog("CastSprint Decoder: VTDecompressionSessionCreate failed with OSStatus %d", sessionStatus)
            return false
        }

        // Configure real-time low-latency mode
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)

        self.decompressionSession = session
        self.hasReceivedKeyframe = false
        NSLog("CastSprint Decoder: Hardware H.264 decompressor ready (%dx%d)", outputWidth, outputHeight)
        return true
    }

    /// Decodes an incoming Annex-B video access unit
    public func decode(configId: UInt32, isKeyframe: Bool, ptsMicros: UInt64, annexBData: Data) -> Bool {
        guard let session = decompressionSession, let formatDesc = formatDescription else {
            return false
        }

        // Drop delta frames until a valid IDR keyframe arrives
        if !hasReceivedKeyframe {
            if !isKeyframe {
                totalFramesDropped += 1
                return false
            }
            hasReceivedKeyframe = true
        }

        // 1. Convert Annex-B to AVCC (length-prefixed NALUs)
        let avccData = convertAnnexBToAvcc(annexB: annexBData)
        guard avccData.count > 4 else { return false }

        // 2. Wrap AVCC data in CMBlockBuffer
        var blockBuffer: CMBlockBuffer?
        let blockStatus = avccData.withUnsafeBytes { rawPtr in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: avccData.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avccData.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }

        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer = blockBuffer else {
            return false
        }

        // Copy bytes into block buffer
        _ = avccData.withUnsafeBytes { rawPtr in
            CMBlockBufferReplaceDataBytes(

                with: rawPtr.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }

        // 3. Create CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: Int64(ptsMicros), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )

        var sampleSize = avccData.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )


        guard sampleStatus == noErr, let sampleBuffer = sampleBuffer else {
            return false
        }

        // 4. Submit to VideoToolbox Hardware Decompressor
        let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression, ._1xRealTimePlayback]
        var outputFlags: VTDecodeInfoFlags = []

        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: decodeFlags,
            frameRefcon: nil,
            infoFlagsOut: &outputFlags
        )

        return decodeStatus == noErr
    }

    private func handleDecompressedFrame(status: OSStatus, pixelBuffer: CVImageBuffer?, pts: CMTime) {
        guard status == noErr, let pixelBuffer = pixelBuffer else {
            if status != noErr {
                delegate?.didEncounterDecoderError(NSError(domain: "VideoToolbox", code: Int(status), userInfo: nil))
            }
            return
        }

        totalFramesDecoded += 1
        let ptsMicros = UInt64(CMTimeGetSeconds(pts) * 1_000_000)
        delegate?.didDecompressPixelBuffer(pixelBuffer, ptsMicros: ptsMicros)
    }

    // MARK: - Annex-B & Parameter Set Helpers

    private func extractParameterSets(from data: Data) -> [Data] {
        var nalus: [Data] = []
        var offset = 0
        let count = data.count

        while offset < count {
            // Find start code (0x00000001 or 0x000001)
            if let start = findNextStartCode(in: data, from: offset) {
                let naluStart = start.prefixLength + start.offset
                let nextStart = findNextStartCode(in: data, from: naluStart)
                let naluEnd = nextStart?.offset ?? count
                if naluEnd > naluStart {
                    nalus.append(data.subdata(in: naluStart..<naluEnd))
                }
                offset = naluEnd
            } else {
                break
            }
        }
        return nalus
    }

    private func findNextStartCode(in data: Data, from offset: Int) -> (offset: Int, prefixLength: Int)? {
        guard offset + 3 <= data.count else { return nil }
        for i in offset..<(data.count - 3) {
            if data[i] == 0x00 && data[i+1] == 0x00 {
                if data[i+2] == 0x01 {
                    return (offset: i, prefixLength: 3)
                } else if i + 3 < data.count && data[i+2] == 0x00 && data[i+3] == 0x01 {
                    return (offset: i, prefixLength: 4)
                }
            }
        }
        return nil
    }

    private func isSpsNALU(_ nalu: Data) -> Bool {
        guard !nalu.isEmpty else { return false }
        let type = nalu[0] & 0x1F
        return type == 7 // H.264 SPS
    }

    private func isPpsNALU(_ nalu: Data) -> Bool {
        guard !nalu.isEmpty else { return false }
        let type = nalu[0] & 0x1F
        return type == 8 // H.264 PPS
    }

    private func convertAnnexBToAvcc(annexB: Data) -> Data {
        var avcc = Data()
        var offset = 0
        let count = annexB.count

        while offset < count {
            if let start = findNextStartCode(in: annexB, from: offset) {
                let naluStart = start.prefixLength + start.offset
                let nextStart = findNextStartCode(in: annexB, from: naluStart)
                let naluEnd = nextStart?.offset ?? count
                let naluLen = naluEnd - naluStart
                if naluLen > 0 {
                    var lenBigEndian = CFSwapInt32HostToBig(UInt32(naluLen))
                    avcc.append(Data(bytes: &lenBigEndian, count: 4))
                    avcc.append(annexB.subdata(in: naluStart..<naluEnd))
                }
                offset = naluEnd
            } else {
                // If already without start code
                if offset == 0 {
                    var lenBigEndian = CFSwapInt32HostToBig(UInt32(count))
                    avcc.append(Data(bytes: &lenBigEndian, count: 4))
                    avcc.append(annexB)
                }
                break
            }
        }
        return avcc
    }
}
