// VideoToolboxEncoder.swift — iOS Hardware H.264 / HEVC Real-Time Video Compression
import Foundation
import VideoToolbox
import CoreMedia

public protocol VideoEncoderDelegate: AnyObject {
    func didProduceConfigData(configId: UInt32, width: UInt16, height: UInt16, fps: UInt16, bitrate: UInt32, csd: Data)
    func didProduceVideoFrame(configId: UInt32, ptsMicros: UInt64, isKeyframe: Bool, data: Data)
    func encoderDidEncounterError(_ error: Error)
}

public final class VideoToolboxEncoder {
    public weak var delegate: VideoEncoderDelegate?

    private var compressionSession: VTCompressionSession?
    public private(set) var width: Int32 = 1920
    public private(set) var height: Int32 = 1080
    public private(set) var fps: Int32 = 60
    public private(set) var bitrateBps: Int32 = 12_000_000
    public private(set) var isConfigured: Bool = false

    private var currentConfigId: UInt32 = 1
    private var hasDispatchedConfig: Bool = false
    private let encodeQueue = DispatchQueue(label: "com.castsprint.ios.encoder", qos: .userInteractive)

    public init() {}

    deinit {
        teardown()
    }

    public static func isHardwareAccelerated() -> Bool {
        return true // All modern iOS devices (A10+) support hardware H.264/HEVC encoding
    }

    public func setup(
        width: Int32,
        height: Int32,
        fps: Int32 = 60,
        bitrateBps: Int32 = 12_000_000,
        useHevc: Bool = false
    ) -> Bool {
        teardown()

        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateBps = bitrateBps

        let codec = useHevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        var session: VTCompressionSession?

        let callback: VTCompressionOutputCallback = { outputCallbackRefCon, _, status, infoFlags, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else { return }
            let encoder = Unmanaged<VideoToolboxEncoder>.fromOpaque(refCon).takeUnretainedValue()
            encoder.handleEncodedSampleBuffer(sampleBuffer, infoFlags: infoFlags)
        }

        let pixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height
        ]

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: codec,
            encoderSpecification: nil,
            imageBufferAttributes: pixelBufferAttributes as CFDictionary,
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

        // Hard cap keyframe interval to 1.5 seconds for rapid recovery on packet loss
        let maxKeyframeInterval = fps * 3 / 2
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: maxKeyframeInterval as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1.5 as CFNumber)

        // Zero-latency: Disable B-frames and frame reordering
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        // Data rate limit (burst protection)
        let byteRate = bitrateBps / 8
        let rateLimits: [CFNumber] = [byteRate as CFNumber, 1.0 as CFNumber]
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: rateLimits as CFArray)

        let prepStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepStatus == noErr else {
            NSLog("CastSprint: VTCompressionSessionPrepareToEncodeFrames failed with %d", prepStatus)
            return false
        }

        self.compressionSession = session
        self.isConfigured = true
        self.hasDispatchedConfig = false
        self.currentConfigId &+= 1
        return true
    }

    private var forceNextKeyframe: Bool = false

    public func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let session = compressionSession, isConfigured else { return }

        // Dynamic resolution / orientation check
        let pbWidth = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let pbHeight = Int32(CVPixelBufferGetHeight(pixelBuffer))
        if pbWidth != width || pbHeight != height {
            // Resolution changed (e.g. device rotated), reconfigure encoder immediately
            if !setup(width: pbWidth, height: pbHeight, fps: fps, bitrateBps: bitrateBps) {
                return
            }
        }

        var frameProperties: [CFString: Any]? = nil
        if forceNextKeyframe {
            frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue as Any]
            forceNextKeyframe = false
        }

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: frameProperties as CFDictionary?,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    public func requestKeyframe() {
        forceNextKeyframe = true
    }

    public func teardown() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            self.compressionSession = nil
        }
        self.isConfigured = false
        self.hasDispatchedConfig = false
    }

    // MARK: - Sample Buffer Handler

    private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer, infoFlags: VTEncodeInfoFlags) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
        var isKeyframe = true
        if let attachments = attachments, CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
            isKeyframe = !CFDictionaryContainsKey(dict, unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self))
        }

        // 1. Dispatch SPS/PPS on first keyframe or config change
        if isKeyframe && !hasDispatchedConfig, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            if let configData = extractAnnexBSpsPps(formatDesc: formatDesc) {
                delegate?.didProduceConfigData(
                    configId: currentConfigId,
                    width: UInt16(width),
                    height: UInt16(height),
                    fps: UInt16(fps),
                    bitrate: UInt32(bitrateBps),
                    csd: configData
                )
                hasDispatchedConfig = true
            }
        }

        // 2. Extract NAL units
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength: size_t = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let ptrStatus = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard ptrStatus == noErr, let dataPointer = dataPointer, totalLength > 4 else { return }

        // Convert AVCC length headers (4-byte big-endian) to Annex-B start codes (0x00000001)
        var rawData = Data(bytes: dataPointer, count: totalLength)
        convertToAnnexB(in: &rawData)

        let ptsSeconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let ptsMicros = UInt64(ptsSeconds * 1_000_000.0)

        delegate?.didProduceVideoFrame(
            configId: currentConfigId,
            ptsMicros: ptsMicros,
            isKeyframe: isKeyframe,
            data: rawData
        )
    }

    private func extractAnnexBSpsPps(formatDesc: CMFormatDescription) -> Data? {
        var count: size_t = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDesc,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: nil
        )

        guard status == noErr, count > 0 else { return nil }

        var config = Data()
        for idx in 0..<count {
            var pointer: UnsafePointer<UInt8>?
            var size: size_t = 0
            let pStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: idx,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )

            if pStatus == noErr, let ptr = pointer, size > 0 {
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
