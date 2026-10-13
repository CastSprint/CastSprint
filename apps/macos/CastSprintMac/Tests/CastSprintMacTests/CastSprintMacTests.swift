// CastSprintMacTests.swift — Unit Tests for CastSprint macOS Engine
import XCTest
import CCastSprintProtocol

final class CastSprintMacTests: XCTestCase {

    func testProtocolCAbiGoldenHeartbeat() {
        var buffer = [UInt8](repeating: 0, count: 64)
        let bytesWritten = csp_encode_heartbeat_message(
            0x00000001,
            0x00000002,
            0x0102030405060708,
            0x1112131415161718,
            &buffer,
            buffer.count
        )

        XCTAssertEqual(bytesWritten, 40)

        // Exact golden vector
        let expectedGolden: [UInt8] = [
            0x43, 0x53, 0x50, 0x52, 0x01, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18
        ]

        XCTAssertEqual(Array(buffer[0..<40]), expectedGolden)

        // Decode Header
        var header = CspHeader()
        let decodeRes = csp_decode_header(&buffer, 40, &header)
        XCTAssertEqual(decodeRes, CSP_DECODE_OK)
        XCTAssertEqual(header.version, UInt8(CSP_VERSION))
        XCTAssertEqual(header.type, UInt8(CSP_MSG_HEARTBEAT.rawValue))
        XCTAssertEqual(header.session_id, 1)
        XCTAssertEqual(header.sequence, 2)
        XCTAssertEqual(header.payload_length, 16)

        // Decode Heartbeat Payload
        var ts: UInt64 = 0
        var echo: UInt64 = 0
        let payloadSlice = Array(buffer[24..<40])
        let ok = csp_decode_heartbeat_payload(payloadSlice, 16, &ts, &echo)
        XCTAssertTrue(ok)
        XCTAssertEqual(ts, 0x0102030405060708)
        XCTAssertEqual(echo, 0x1112131415161718)
    }

    func testVideoFramePrefixCodec() {
        var prefix = [UInt8](repeating: 0, count: 16)
        let ok = csp_encode_video_frame_prefix(42, UInt32(CSP_FRAME_KEYFRAME), 987654321, &prefix, 16)
        XCTAssertTrue(ok)

        var configId: UInt32 = 0
        var flags: UInt32 = 0
        var pts: UInt64 = 0
        var dataOffset: size_t = 0
        let decOk = csp_decode_video_frame_prefix(prefix, 16, &configId, &flags, &pts, &dataOffset)
        XCTAssertTrue(decOk)
        XCTAssertEqual(configId, 42)
        XCTAssertEqual(flags, UInt32(CSP_FRAME_KEYFRAME))
        XCTAssertEqual(pts, 987654321)
        XCTAssertEqual(dataOffset, 16)
    }

    func testPlatformCapabilitiesGating() {
        let caps = (CSP_CAP_PLATFORM_MACOS | CSP_CAP_PLATFORM_IOS | CSP_CAP_VIDEO_H264)
        XCTAssertNotEqual(caps & UInt32(CSP_CAP_PLATFORM_MACOS), 0)
        XCTAssertNotEqual(caps & UInt32(CSP_CAP_PLATFORM_IOS), 0)
        XCTAssertEqual(caps & UInt32(CSP_CAP_PLATFORM_WINDOWS), 0)
    }
}
