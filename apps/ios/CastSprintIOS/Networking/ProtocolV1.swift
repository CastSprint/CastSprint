// ProtocolV1.swift — CastSprint Protocol v1 Swift Implementation
// Strictly adheres to docs/architecture/PROTOCOL.md
import Foundation

public enum MessageType: UInt8 {
    case hello          = 0x01
    case helloAck       = 0x02
    case videoConfig    = 0x10
    case videoFrame     = 0x11
    case audioConfig    = 0x20
    case audioFrame     = 0x21
    case displayChanged = 0x30
    case heartbeat      = 0x40
    case status         = 0x41
    case disconnect     = 0x50
    case error          = 0x51

    public var isMedia: Bool {
        return self == .videoFrame || self == .audioFrame
    }
}

public struct ProtocolV1Constants {
    public static let magic: UInt32 = 0x43535052 // "CSPR"
    public static let version: UInt8 = 1
    public static let headerSize: Int = 24
    public static let maxPayloadSize: Int = 8 * 1024 * 1024       // 8 MiB
    public static let maxControlPayloadSize: Int = 64 * 1024     // 64 KiB
    public static let maxStringBytes: Int = 256
    public static let defaultPort: UInt16 = 27183

    // Capability flags
    public static let capVideoH264: UInt32       = 1 << 0
    public static let capAudio: UInt32           = 1 << 1
    public static let capVideoH265: UInt32       = 1 << 2
    public static let capPlatformAndroid: UInt32 = 1 << 3
    public static let capPlatformIOS: UInt32     = 1 << 4
    public static let capPlatformMacOS: UInt32   = 1 << 5
    public static let capPlatformWindows: UInt32 = 1 << 6

    // Frame flags
    public static let frameKeyframe: UInt32      = 1 << 0
    public static let frameDiscontinuity: UInt32 = 1 << 1
    public static let frameEndOfStream: UInt32   = 1 << 2

    // Audio codecs
    public static let audioCodecOpus: UInt8  = 1
    public static let audioCodecAAC: UInt8   = 2
    public static let audioCodecPCM16: UInt8 = 3
}

public struct ProtocolHeader {
    public let version: UInt8
    public let type: MessageType
    public let flags: UInt16
    public let sessionId: UInt32
    public let sequence: UInt32
    public let payloadLength: UInt32

    public init(type: MessageType, sessionId: UInt32, sequence: UInt32, payloadLength: UInt32, flags: UInt16 = 0) {
        self.version = ProtocolV1Constants.version
        self.type = type
        self.flags = flags
        self.sessionId = sessionId
        self.sequence = sequence
        self.payloadLength = payloadLength
    }
}

public enum HeaderDecodeResult {
    case ok(ProtocolHeader)
    case needMoreData
    case invalid(String)
}

public final class ProtocolCodec {

    public static func encodeHeader(_ header: ProtocolHeader) -> Data {
        var data = Data(count: ProtocolV1Constants.headerSize)
        data.withUnsafeMutableBytes { (rawPtr: UnsafeMutableRawBufferPointer) in
            rawPtr.storeBytes(of: ProtocolV1Constants.magic.bigEndian, toByteOffset: 0, as: UInt32.self)
            rawPtr.storeBytes(of: header.version, toByteOffset: 4, as: UInt8.self)
            rawPtr.storeBytes(of: header.type.rawValue, toByteOffset: 5, as: UInt8.self)
            rawPtr.storeBytes(of: header.flags.bigEndian, toByteOffset: 6, as: UInt16.self)
            rawPtr.storeBytes(of: header.sessionId.bigEndian, toByteOffset: 8, as: UInt32.self)
            rawPtr.storeBytes(of: header.sequence.bigEndian, toByteOffset: 12, as: UInt32.self)
            rawPtr.storeBytes(of: header.payloadLength.bigEndian, toByteOffset: 16, as: UInt32.self)
            rawPtr.storeBytes(of: UInt32(0), toByteOffset: 20, as: UInt32.self) // reserved = 0
        }
        return data
    }

    public static func decodeHeader(_ data: Data, offset: Int = 0) -> HeaderDecodeResult {
        guard data.count - offset >= ProtocolV1Constants.headerSize else {
            return .needMoreData
        }

        return data.withUnsafeBytes { rawPtr -> HeaderDecodeResult in
            let base = rawPtr.baseAddress! + offset

            let magic = base.load(fromByteOffset: 0, as: UInt32.self).bigEndian
            if magic != ProtocolV1Constants.magic {
                return .invalid("Bad magic: \(String(format: "0x%08X", magic))")
            }

            let version = base.load(fromByteOffset: 4, as: UInt8.self)
            if version != ProtocolV1Constants.version {
                return .invalid("Unsupported protocol version: \(version)")
            }

            let typeRaw = base.load(fromByteOffset: 5, as: UInt8.self)
            guard let type = MessageType(rawValue: typeRaw) else {
                return .invalid("Unknown message type: \(typeRaw)")
            }

            let flags = base.load(fromByteOffset: 6, as: UInt16.self).bigEndian
            let sessionId = base.load(fromByteOffset: 8, as: UInt32.self).bigEndian
            let sequence = base.load(fromByteOffset: 12, as: UInt32.self).bigEndian
            let payloadLen = base.load(fromByteOffset: 16, as: UInt32.self).bigEndian
            let reserved = base.load(fromByteOffset: 20, as: UInt32.self).bigEndian

            if flags != 0 || reserved != 0 {
                return .invalid("Reserved bits must be zero")
            }

            let limit = type.isMedia ? ProtocolV1Constants.maxPayloadSize : ProtocolV1Constants.maxControlPayloadSize
            if payloadLen > UInt32(limit) {
                return .invalid("Payload length \(payloadLen) exceeds limit \(limit)")
            }

            let header = ProtocolHeader(type: type, sessionId: sessionId, sequence: sequence, payloadLength: payloadLen, flags: flags)
            return .ok(header)
        }
    }

    public static func encodeMessage(type: MessageType, sessionId: UInt32, sequence: UInt32, payload: Data) -> Data {
        let header = ProtocolHeader(type: type, sessionId: sessionId, sequence: sequence, payloadLength: UInt32(payload.count))
        var msg = encodeHeader(header)
        msg.append(payload)
        return msg
    }

    public static func helloPayload(
        capabilities: UInt32,
        osVersion: UInt16,
        width: UInt16,
        height: UInt16,
        densityDpi: UInt16,
        deviceName: String,
        deviceModel: String
    ) -> Data {
        let nameBytes = Array(deviceName.utf8.prefix(ProtocolV1Constants.maxStringBytes))
        let modelBytes = Array(deviceModel.utf8.prefix(ProtocolV1Constants.maxStringBytes))

        let totalLen = 16 + 2 + nameBytes.count + 2 + modelBytes.count
        var payload = Data(count: totalLen)

        payload.withUnsafeMutableBytes { rawPtr in
            let base = rawPtr.baseAddress!
            base.storeBytes(of: UInt8(1), toByteOffset: 0, as: UInt8.self) // min_ver
            base.storeBytes(of: UInt8(1), toByteOffset: 1, as: UInt8.self) // max_ver
            base.storeBytes(of: UInt16(0), toByteOffset: 2, as: UInt16.self) // reserved
            base.storeBytes(of: capabilities.bigEndian, toByteOffset: 4, as: UInt32.self)
            base.storeBytes(of: osVersion.bigEndian, toByteOffset: 8, as: UInt16.self)
            base.storeBytes(of: width.bigEndian, toByteOffset: 10, as: UInt16.self)
            base.storeBytes(of: height.bigEndian, toByteOffset: 12, as: UInt16.self)
            base.storeBytes(of: densityDpi.bigEndian, toByteOffset: 14, as: UInt16.self)
        }

        var offset = 16
        let nameLen = UInt16(nameBytes.count).bigEndian
        withUnsafeBytes(of: nameLen) { payload.replaceSubrange(offset..<offset+2, with: $0) }
        offset += 2
        payload.replaceSubrange(offset..<offset+nameBytes.count, with: nameBytes)
        offset += nameBytes.count

        let modelLen = UInt16(modelBytes.count).bigEndian
        withUnsafeBytes(of: modelLen) { payload.replaceSubrange(offset..<offset+2, with: $0) }
        offset += 2
        payload.replaceSubrange(offset..<offset+modelBytes.count, with: modelBytes)

        return payload
    }

    public struct HelloAck {
        public let status: UInt8
        public let acceptedVersion: UInt8
        public let sessionId: UInt32
        public let maxPayloadSize: UInt32
    }

    public static func decodeHelloAck(_ payload: Data) -> HelloAck? {
        guard payload.count >= 12 else { return nil }
        return payload.withUnsafeBytes { rawPtr -> HelloAck? in
            let base = rawPtr.baseAddress!
            let status = base.load(fromByteOffset: 0, as: UInt8.self)
            let acceptedVer = base.load(fromByteOffset: 1, as: UInt8.self)
            let reserved = base.load(fromByteOffset: 2, as: UInt16.self)
            if reserved != 0 { return nil }
            let sessionId = base.load(fromByteOffset: 4, as: UInt32.self).bigEndian
            let maxPayload = base.load(fromByteOffset: 8, as: UInt32.self).bigEndian
            return HelloAck(status: status, acceptedVersion: acceptedVer, sessionId: sessionId, maxPayloadSize: maxPayload)
        }
    }

    public static func videoConfigPayload(
        configId: UInt32,
        codec: UInt8 = 1, // 1 = H.264, 2 = H.265
        profile: UInt8 = 66, // Baseline
        level: UInt8 = 42,
        rotation: UInt8 = 0,
        width: UInt16,
        height: UInt16,
        fps: UInt16,
        bitrate: UInt32,
        csd: Data
    ) -> Data {
        var payload = Data(count: 24 + csd.count)
        payload.withUnsafeMutableBytes { rawPtr in
            let base = rawPtr.baseAddress!
            base.storeBytes(of: configId.bigEndian, toByteOffset: 0, as: UInt32.self)
            base.storeBytes(of: codec, toByteOffset: 4, as: UInt8.self)
            base.storeBytes(of: profile, toByteOffset: 5, as: UInt8.self)
            base.storeBytes(of: level, toByteOffset: 6, as: UInt8.self)
            base.storeBytes(of: rotation, toByteOffset: 7, as: UInt8.self)
            base.storeBytes(of: width.bigEndian, toByteOffset: 8, as: UInt16.self)
            base.storeBytes(of: height.bigEndian, toByteOffset: 10, as: UInt16.self)
            base.storeBytes(of: fps.bigEndian, toByteOffset: 12, as: UInt16.self)
            base.storeBytes(of: UInt16(0), toByteOffset: 14, as: UInt16.self) // reserved
            base.storeBytes(of: bitrate.bigEndian, toByteOffset: 16, as: UInt32.self)
            base.storeBytes(of: UInt32(csd.count).bigEndian, toByteOffset: 20, as: UInt32.self)
        }
        if !csd.isEmpty {
            payload.replaceSubrange(24..<24+csd.count, with: csd)
        }
        return payload
    }

    public static func videoFramePrefix(configId: UInt32, isKeyframe: Bool, ptsUs: UInt64) -> Data {
        var prefix = Data(count: 16)
        prefix.withUnsafeMutableBytes { rawPtr in
            let base = rawPtr.baseAddress!
            base.storeBytes(of: configId.bigEndian, toByteOffset: 0, as: UInt32.self)
            let flags: UInt32 = isKeyframe ? ProtocolV1Constants.frameKeyframe : 0
            base.storeBytes(of: flags.bigEndian, toByteOffset: 4, as: UInt32.self)
            base.storeBytes(of: ptsUs.bigEndian, toByteOffset: 8, as: UInt64.self)
        }
        return prefix
    }

    public static func audioConfigPayload(
        codec: UInt8 = ProtocolV1Constants.audioCodecAAC,
        channels: UInt8 = 2,
        sampleRate: UInt32 = 48000,
        csd: Data = Data()
    ) -> Data {
        var payload = Data(count: 12 + csd.count)
        payload.withUnsafeMutableBytes { rawPtr in
            let base = rawPtr.baseAddress!
            base.storeBytes(of: codec, toByteOffset: 0, as: UInt8.self)
            base.storeBytes(of: channels, toByteOffset: 1, as: UInt8.self)
            base.storeBytes(of: UInt16(0), toByteOffset: 2, as: UInt16.self) // reserved
            base.storeBytes(of: sampleRate.bigEndian, toByteOffset: 4, as: UInt32.self)
            base.storeBytes(of: UInt32(csd.count).bigEndian, toByteOffset: 8, as: UInt32.self)
        }
        if !csd.isEmpty {
            payload.replaceSubrange(12..<12+csd.count, with: csd)
        }
        return payload
    }

    public static func audioFramePrefix(ptsUs: UInt64) -> Data {
        var prefix = Data(count: 8)
        prefix.withUnsafeMutableBytes { rawPtr in
            rawPtr.storeBytes(of: ptsUs.bigEndian, toByteOffset: 0, as: UInt64.self)
        }
        return prefix
    }

    public static func heartbeatPayload(timestampUs: UInt64, echoTimestampUs: UInt64) -> Data {
        var payload = Data(count: 16)
        payload.withUnsafeMutableBytes { rawPtr in
            let base = rawPtr.baseAddress!
            base.storeBytes(of: timestampUs.bigEndian, toByteOffset: 0, as: UInt64.self)
            base.storeBytes(of: echoTimestampUs.bigEndian, toByteOffset: 8, as: UInt64.self)
        }
        return payload
    }

    public static func disconnectPayload(reason: UInt16, message: String) -> Data {
        let msgBytes = Array(message.utf8.prefix(ProtocolV1Constants.maxStringBytes))
        var payload = Data(count: 4 + msgBytes.count)
        payload.withUnsafeMutableBytes { rawPtr in
            let base = rawPtr.baseAddress!
            base.storeBytes(of: reason.bigEndian, toByteOffset: 0, as: UInt16.self)
            base.storeBytes(of: UInt16(msgBytes.count).bigEndian, toByteOffset: 2, as: UInt16.self)
        }
        if !msgBytes.isEmpty {
            payload.replaceSubrange(4..<4+msgBytes.count, with: msgBytes)
        }
        return payload
    }
}
