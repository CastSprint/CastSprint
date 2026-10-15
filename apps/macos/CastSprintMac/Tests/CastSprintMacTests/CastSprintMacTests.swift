// CastSprintMacTests.swift — Unit Tests for CastSprint macOS Engine
import XCTest
import CCastSprintProtocol
@testable import CastSprintMac

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

    func testVideoToolboxDecoderSpsPpsConfiguration() {
        let decoder = VideoToolboxDecoder()


        // Golden 1080p High Profile SPS + PPS Annex-B
        let spsPps: [UInt8] = [
            0x00, 0x00, 0x00, 0x01, 0x27, 0x64, 0x00, 0x28, 0xAC, 0x56, 0x50, 0x1E, 0x00, 0x89, 0xF9, 0x50,
            0x00, 0x00, 0x00, 0x01, 0x28, 0xEE, 0x3C, 0xB0
        ]


        let ok = decoder.configureH264(configId: 1, csdAnnexB: Data(spsPps), width: 1920, height: 1080)
        XCTAssertTrue(ok, "VideoToolbox hardware decompressor should configure successfully with golden SPS/PPS")
        XCTAssertNotNil(decoder.formatDescription)
        XCTAssertNotNil(decoder.decompressionSession)
    }

    func testVideoToolboxDecoderUsesSPSDimensionsWhenCallerDoesNotKnowThem() {
        let decoder = VideoToolboxDecoder()
        let spsPps: [UInt8] = [
            0x00, 0x00, 0x00, 0x01, 0x27, 0x64, 0x00, 0x28, 0xAC, 0x56, 0x50, 0x1E, 0x00, 0x89, 0xF9, 0x50,
            0x00, 0x00, 0x00, 0x01, 0x28, 0xEE, 0x3C, 0xB0
        ]

        XCTAssertTrue(decoder.configureH264(configId: 1, csdAnnexB: Data(spsPps), width: 0, height: 0))
        XCTAssertGreaterThan(decoder.decodedWidth, 0)
        XCTAssertGreaterThan(decoder.decodedHeight, 0)
    }

    func testHelloHandshakeCAbi() {
        var minVer: UInt8 = 0, maxVer: UInt8 = 0
        var caps: UInt32 = 0, apiLevel: UInt16 = 0
        var width: UInt16 = 0, height: UInt16 = 0, dpi: UInt16 = 0
        var nameBuf = [CChar](repeating: 0, count: 64)
        var modelBuf = [CChar](repeating: 0, count: 64)

        // Construct HELLO payload: 16 bytes header + 2-byte len + name + 2-byte len + model
        let devName = "Pixel 8"
        let devModel = "Google Pixel"
        let nameBytes = Array(devName.utf8)
        let modelBytes = Array(devModel.utf8)

        var payload = [UInt8](repeating: 0, count: 16 + 2 + nameBytes.count + 2 + modelBytes.count)
        payload[0] = 1 // min_ver
        payload[1] = 1 // max_ver
        payload[8] = 0; payload[9] = 34 // api_level 34
        payload[10] = 0x07; payload[11] = 0x80 // 1920
        payload[12] = 0x04; payload[13] = 0x38 // 1080
        payload[14] = 0x01; payload[15] = 0xA4 // 420 dpi

        var off = 16
        payload[off] = UInt8(nameBytes.count >> 8); payload[off+1] = UInt8(nameBytes.count & 0xFF)
        off += 2
        payload.replaceSubrange(off..<off+nameBytes.count, with: nameBytes)
        off += nameBytes.count

        payload[off] = UInt8(modelBytes.count >> 8); payload[off+1] = UInt8(modelBytes.count & 0xFF)
        off += 2
        payload.replaceSubrange(off..<off+modelBytes.count, with: modelBytes)

        let ok = csp_decode_hello_payload(
            payload, payload.count,
            &minVer, &maxVer, &caps, &apiLevel, &width, &height, &dpi,
            &nameBuf, nameBuf.count, &modelBuf, modelBuf.count
        )

        XCTAssertTrue(ok)
        XCTAssertEqual(minVer, 1)
        XCTAssertEqual(maxVer, 1)
        XCTAssertEqual(width, 1920)
        XCTAssertEqual(height, 1080)
        XCTAssertEqual(String(cString: nameBuf), devName)
        XCTAssertEqual(String(cString: modelBuf), devModel)

        // Verify HELLO_ACK encoding
        var ackBuf = [UInt8](repeating: 0, count: 36)
        let written = csp_encode_hello_ack_message(
            12345, 1, 0, 1, 8 * 1024 * 1024,
            &ackBuf, ackBuf.count
        )
        XCTAssertEqual(written, 36)
    }

    func testUnifiedDeviceModel() {
        let iosUsb = UnifiedDevice(

            id: "ios-1",
            name: "iPhone 15 Pro",
            model: "iPhone15,3",
            platform: .ios,
            transport: .usb,
            status: .ready
        )
        XCTAssertEqual(iosUsb.systemIcon, "iphone")
        XCTAssertEqual(iosUsb.platform, .ios)
        XCTAssertEqual(iosUsb.transport, .usb)

        let androidUsb = UnifiedDevice(
            id: "adb-emulator-5554",
            name: "Pixel 8 Pro",
            model: "emulator-5554",
            platform: .android,
            transport: .usb,
            status: .ready,
            adbSerial: "emulator-5554"
        )
        XCTAssertEqual(androidUsb.systemIcon, "cable.connector")
        XCTAssertEqual(androidUsb.adbSerial, "emulator-5554")

        let testDev = UnifiedDevice(
            id: "test-sim",
            name: "Test Simulator",
            model: "Sim",
            platform: .ios,
            transport: .wifi,
            isTestDevice: true
        )
        XCTAssertEqual(testDev.systemIcon, "testtube.2")
        XCTAssertTrue(testDev.isTestDevice)
    }

    func testConnectionProviderSuite() {
        let providers: [ConnectionProvider] = [
            IPhoneUsbCaptureProvider(),
            IPhoneCastSprintLanProvider(),
            AndroidUsbAdbProvider(),
            AndroidLanProvider(),
            AndroidWirelessAdbProvider(),
            HotspotLanProvider(),
            AirPlaySystemIntegration(),
            ExperimentalUsbNetworkProvider(),
            OptionalBluetoothDiscoveryProvider()
        ]

        XCTAssertEqual(providers.count, 9)
        for p in providers {
            XCTAssertFalse(p.providerId.isEmpty)
            XCTAssertFalse(p.displayName.isEmpty)
            XCTAssertFalse(p.capabilityDescription.isEmpty)
            XCTAssertFalse(p.statusText.isEmpty)
        }

        // Verify specific categories
        let usbProviders = providers.filter { $0.category == .usb }
        XCTAssertEqual(usbProviders.count, 2) // iPhone USB + Android USB

        let lanProviders = providers.filter { $0.category == .lan }
        XCTAssertEqual(lanProviders.count, 2) // iPhone LAN + Android LAN

        let airPlay = providers.first { $0.category == .systemAirPlay }
        XCTAssertNotNil(airPlay)
        XCTAssertEqual(airPlay?.implementationStatus, "VERIFIED_WORKING")
    }

    func testWirelessAdbDeviceClassification() {
        let wirelessAndroid = AndroidDevice(id: "192.168.1.100:5555", model: "Galaxy S23", state: "device")
        XCTAssertTrue(wirelessAndroid.isAuthorized)
        XCTAssertTrue(wirelessAndroid.id.contains(":"))
    }
}

