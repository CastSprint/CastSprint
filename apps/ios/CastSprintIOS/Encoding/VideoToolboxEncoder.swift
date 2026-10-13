// VideoToolboxEncoder.swift — iOS Hardware H.264 / HEVC Video Compression
import Foundation
import VideoToolbox
import CoreMedia

public protocol VideoEncoderDelegate: AnyObject {
    func didProduceConfigData(_ configData: Data)
    func didProduceVideoFrame(ptsMicros: UInt64, isKeyframe: Bool, data: Data)
}

public final class VideoToolboxEncoder {
    private var compressionSession: VTCompressionSession?
    public weak var delegate: VideoEncoderDelegate?

    private var currentConfigId: UInt32 = 1
    private var hasDispatchedConfig = false

    public init() {}

    public func setup(width: Int32, height: Int32, fps: Int32, bitrateBps: Int32, useHevc: Bool = false) -> Bool {
        teardown()

        let codec = useHevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        var session: VTCompressionSession?

        let callback: VTCompressionOutputCallback = { outputCallbackRefCon, _, status, infoFlags, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else { return }
            let encoder = Unmanaged<VideoToolboxEncoder>.fromOpaque(refCon).takeUnretainedValue()
            encoder.handleEncodedSampleBuffer(sampleBuffer, infoFlags: infoFlags)
        }

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: codec,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: callback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            NSLog("CastSprint: VTCompressionSessionCreate failed with %d", status)
            return false
        }

        // Configure ultra-low-latency real-time properties
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateBps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (fps * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        VTCompressionSessionPrepareToEncodeFrames(session)
        self.compressionSession = session
        self.hasDispatchedConfig = false
        return true
    }

    public func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let session = compressionSession else { return }

        let flags: VTEncodeInfoFlags = []
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: nil,
            infoFlagsOut: nil
        )
    }

    public func teardown() {
        guard let session = compressionSession else { return }
        VTCompressionSessionInvalidate(session)
        self.compressionSession = nil
        self.hasDispatchedConfig = false
    }

    private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer, infoFlags: VTEncodeInfoFlags) {
        let isKeyframe = !CFDictionaryContainsKey(
            unsafeBitCast(CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false), 0), to: CFDictionary.self),
            unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self)
        )

        // 1. Dispatch SPS/PPS on first keyframe
        if isKeyframe && !hasDispatchedConfig, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            if let configData = extractAnnexBSpsPps(formatDesc: formatDesc) {
                delegate?.didProduceConfigData(configData)
                hasDispatchedConfig = true
            }
        }

        // 2. Extract Annex-B access unit
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength: size_t = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard let dataPointer = dataPointer, totalLength > 4 else { return }

        // Convert AVCC length headers to Annex-B start codes (0x00000001)
        var rawData = Data(bytes: dataPointer, count: totalLength)
        convertToAnnexB(in: &rawData)

        let ptsMicros = UInt64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1_000_000)
        delegate?.didProduceVideoFrame(ptsMicros: ptsMicros, isKeyframe: isKeyframe, data: rawData)
    }

    private func extractAnnexBSpsPps(formatDesc: CMFormatDescription) -> Data? {
        var count: size_t = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)

        var config = Data()
        for idx in 0..<count {
            var pointer: UnsafePointer<UInt8>?
            var size: size_t = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: idx, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            if let ptr = pointer, size > 0 {
                config.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                config.append(ptr, count: size)
            }
        }
        return config.isEmpty ? nil : config
    }

    private func convertToAnnexB(in data: inout Data) {
        var offset = 0
        while offset + 4 <= data.count {
            let length = data.withUnsafeBytes { ptr -> UInt32 in
                let u32 = ptr.load(fromByteOffset: offset, as: UInt32.self)
                return CFSwapInt32BigToHost(u32)
            }
            data.replaceSubrange(offset..<offset+4, with: [0x00, 0x00, 0x00, 0x01])
            offset += 4 + Int(length)
        }
    }
}
