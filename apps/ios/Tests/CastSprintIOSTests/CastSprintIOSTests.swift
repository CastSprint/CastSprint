// CastSprintIOSTests.swift — Automated Unit Tests for CastSprint iOS Core
import XCTest
@testable import CastSprintIOSCore

final class CastSprintIOSTests: XCTestCase {

    // MARK: - 1. Golden Vector Test (docs/architecture/PROTOCOL.md)
    func testGoldenVectorHeartbeat() {
        // HEARTBEAT, session 1, sequence 2, ts 0x0102030405060708, echo 0x1112131415161718
        let goldenBytes: [UInt8] = [
            0x43, 0x53, 0x50, 0x52, 0x01, 0x40, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02,
            0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18
        ]
        let goldenData = Data(goldenBytes)

        let headerResult = ProtocolCodec.decodeHeader(goldenData)
        guard case .ok(let hdr) = headerResult else {
            XCTFail("Failed to decode golden header")
            return
        }

        XCTAssertEqual(hdr.version, 1)
        XCTAssertEqual(hdr.type, .heartbeat)
        XCTAssertEqual(hdr.flags, 0)
        XCTAssertEqual(hdr.sessionId, 1)
        XCTAssertEqual(hdr.sequence, 2)
        XCTAssertEqual(hdr.payloadLength, 16)

        let payload = ProtocolCodec.heartbeatPayload(
            timestampUs: 0x0102030405060708,
            echoTimestampUs: 0x1112131415161718
        )
        let generatedMsg = ProtocolCodec.encodeMessage(
            type: .heartbeat,
            sessionId: 1,
            sequence: 2,
            payload: payload
        )

        XCTAssertEqual(generatedMsg, goldenData, "Generated heartbeat message must match golden vector exactly")
    }

    // MARK: - 2. Header Validation Tests
    func testBadMagicRejection() {
        var badData = Data(repeating: 0, count: 24)
        badData[0] = 0x58 // 'X'
        let res = ProtocolCodec.decodeHeader(badData)
        guard case .invalid(let reason) = res else {
            XCTFail("Expected invalid result for bad magic")
            return
        }
        XCTAssertTrue(reason.contains("Bad magic"))
    }

    func testUnsupportedVersionRejection() {
        var badData = Data(count: 24)
        badData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: ProtocolV1Constants.magic.bigEndian, toByteOffset: 0, as: UInt32.self)
            ptr.storeBytes(of: UInt8(99), toByteOffset: 4, as: UInt8.self) // ver 99
        }
        let res = ProtocolCodec.decodeHeader(badData)
        guard case .invalid(let reason) = res else {
            XCTFail("Expected invalid result for version 99")
            return
        }
        XCTAssertTrue(reason.contains("Unsupported protocol version"))
    }

    // MARK: - 3. HELLO & HELLO_ACK Tests
    func testHelloEncodingAndAckDecoding() {
        let payload = ProtocolCodec.helloPayload(
            capabilities: ProtocolV1Constants.capVideoH264 | ProtocolV1Constants.capPlatformIOS,
            osVersion: 18,
            width: 1920,
            height: 1080,
            densityDpi: 460,
            deviceName: "iPhone 16 Pro",
            deviceModel: "A3084"
        )
        XCTAssertGreaterThan(payload.count, 20)

        // Simulate receiver response HELLO_ACK
        var ackPayload = Data(count: 12)
        ackPayload.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: UInt8(0), toByteOffset: 0, as: UInt8.self) // status = 0 Accepted
            ptr.storeBytes(of: UInt8(1), toByteOffset: 1, as: UInt8.self) // accepted version = 1
            ptr.storeBytes(of: UInt16(0), toByteOffset: 2, as: UInt16.self) // reserved = 0
            ptr.storeBytes(of: UInt32(8899).bigEndian, toByteOffset: 4, as: UInt32.self) // session = 8899
            ptr.storeBytes(of: UInt32(8388608).bigEndian, toByteOffset: 8, as: UInt32.self) // max payload = 8 MiB
        }

        let ack = ProtocolCodec.decodeHelloAck(ackPayload)
        XCTAssertNotNil(ack)
        XCTAssertEqual(ack?.status, 0)
        XCTAssertEqual(ack?.acceptedVersion, 1)
        XCTAssertEqual(ack?.sessionId, 8899)
        XCTAssertEqual(ack?.maxPayloadSize, 8388608)
    }

    // MARK: - 4. VIDEO_CONFIG & VIDEO_FRAME Framing
    func testVideoConfigAndFrameFraming() {
        let fakeSpsPps = Data([0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x2A])
        let configPayload = ProtocolCodec.videoConfigPayload(
            configId: 1,
            width: 1920,
            height: 1080,
            fps: 60,
            bitrate: 12_000_000,
            csd: fakeSpsPps
        )
        XCTAssertEqual(configPayload.count, 24 + fakeSpsPps.count)

        let prefix = ProtocolCodec.videoFramePrefix(configId: 1, isKeyframe: true, ptsUs: 500_000)
        XCTAssertEqual(prefix.count, 16)

        prefix.withUnsafeBytes { ptr in
            let cfgId = ptr.load(fromByteOffset: 0, as: UInt32.self).bigEndian
            let flags = ptr.load(fromByteOffset: 4, as: UInt32.self).bigEndian
            let pts = ptr.load(fromByteOffset: 8, as: UInt64.self).bigEndian
            XCTAssertEqual(cfgId, 1)
            XCTAssertEqual(flags, ProtocolV1Constants.frameKeyframe)
            XCTAssertEqual(pts, 500_000)
        }
    }

    // MARK: - 5. AUDIO_CONFIG & AUDIO_FRAME Framing
    func testAudioConfigAndFrameFraming() {
        let fakeAacCsd = Data([0x12, 0x10])
        let audioConfig = ProtocolCodec.audioConfigPayload(
            codec: ProtocolV1Constants.audioCodecAAC,
            channels: 2,
            sampleRate: 48000,
            csd: fakeAacCsd
        )
        XCTAssertEqual(audioConfig.count, 12 + fakeAacCsd.count)

        let audioPrefix = ProtocolCodec.audioFramePrefix(ptsUs: 1_234_567)
        XCTAssertEqual(audioPrefix.count, 8)
        let pts = audioPrefix.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt64.self).bigEndian }
        XCTAssertEqual(pts, 1_234_567)
    }

    // MARK: - 6. PairingInfo URI & CSV Parsing
    func testPairingInfoUriParsing() {
        let uri = "castsprint://connect?host=192.168.1.150&port=27183&fp=A1B2C3D4&token=4829&name=GamingPC"
        let info = PairingInfo.parse(uri)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.host, "192.168.1.150")
        XCTAssertEqual(info?.port, 27183)
        XCTAssertEqual(info?.fingerprintSha256, "A1B2C3D4")
        XCTAssertEqual(info?.sessionToken, "4829")
        XCTAssertEqual(info?.receiverName, "GamingPC")
    }

    func testPairingInfoCsvParsing() {
        let csv = "192.168.1.150, 27183, A1B2C3D4, 4829, LivingRoomMac"
        let info = PairingInfo.parse(csv)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.host, "192.168.1.150")
        XCTAssertEqual(info?.port, 27183)
        XCTAssertEqual(info?.fingerprintSha256, "A1B2C3D4")
        XCTAssertEqual(info?.sessionToken, "4829")
        XCTAssertEqual(info?.receiverName, "LivingRoomMac")
    }

    // MARK: - 7. StreamConfiguration Serialization
    func testStreamConfigurationDefaults() {
        let config = StreamConfiguration(
            receiverHost: "192.168.1.200",
            pairingPin: "1234",
            targetWidth: 1920,
            targetHeight: 1080
        )
        XCTAssertEqual(config.receiverHost, "192.168.1.200")
        XCTAssertEqual(config.receiverPort, 27183)
        XCTAssertEqual(config.targetFps, 60)
        XCTAssertTrue(config.isAudioEnabled)
        XCTAssertFalse(config.isMicrophoneEnabled)
    }
}
