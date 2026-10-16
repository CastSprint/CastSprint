// CastSprintTestSender.swift — Protocol Test Source (Test-Only Simulation)
// Used to validate the macOS receiver with synthetic iPhone/Android network streams.
import Foundation
import Network
import CCastSprintProtocol

public final class CastSprintTestSender {
    private var connection: NWConnection?
    private var timer: Timer?
    private var sequence: UInt32 = 0
    private var sessionId: UInt32 = 0
    private var frameCount: UInt64 = 0

    public private(set) var isStreaming: Bool = false
    public var onLog: ((String) -> Void)?

    public init() {}

    public func start(host: String = "127.0.0.1", port: UInt16 = 27183, simulatedPlatform: String = "iOS", pairingToken: String) {
        stop()

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onLog?("Test Sender: Connected to \(host):\(port). Sending HELLO...")
                self?.sendHello(platform: simulatedPlatform, pairingToken: pairingToken)
            case .failed(let err):
                self?.onLog?("Test Sender: Failed: \(err.localizedDescription)")
                self?.stop()
            default:
                break
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        connection?.cancel()
        connection = nil
        isStreaming = false
        sequence = 0
        sessionId = 0
        frameCount = 0
    }

    private func sendHello(platform: String, pairingToken: String) {
        guard let conn = connection else { return }

        var caps: UInt32 = UInt32(CSP_CAP_VIDEO_H264 | CSP_CAP_AUDIO)
        if platform == "iOS" {
            caps |= UInt32(CSP_CAP_PLATFORM_IOS)
        } else {
            caps |= UInt32(CSP_CAP_PLATFORM_ANDROID)
        }

        let devName = "Test \(platform) Simulator|\(pairingToken)"
        let devModel = platform == "iOS" ? "iPhone 16 Pro" : "Pixel 8 Pro"

        let nameBytes = Array(devName.utf8)
        let modelBytes = Array(devModel.utf8)


        var payload = [UInt8](repeating: 0, count: 16 + 2 + nameBytes.count + 2 + modelBytes.count)
        payload[0] = 1 // min_ver
        payload[1] = 1 // max_ver
        payload[2] = 0; payload[3] = 0 // reserved

        payload[4] = UInt8((caps >> 24) & 0xFF)
        payload[5] = UInt8((caps >> 16) & 0xFF)
        payload[6] = UInt8((caps >> 8) & 0xFF)
        payload[7] = UInt8(caps & 0xFF)

        payload[8] = 0; payload[9] = 34 // api_level (34)
        payload[10] = 0x07; payload[11] = 0x80 // width (1920)
        payload[12] = 0x04; payload[13] = 0x38 // height (1080)
        payload[14] = 0x01; payload[15] = 0xA4 // dpi (420)

        // Strings
        var off = 16
        payload[off] = UInt8((nameBytes.count >> 8) & 0xFF)
        payload[off+1] = UInt8(nameBytes.count & 0xFF)
        off += 2
        payload.replaceSubrange(off..<off+nameBytes.count, with: nameBytes)
        off += nameBytes.count

        payload[off] = UInt8((modelBytes.count >> 8) & 0xFF)
        payload[off+1] = UInt8(modelBytes.count & 0xFF)
        off += 2
        payload.replaceSubrange(off..<off+modelBytes.count, with: modelBytes)

        var header = CspHeader()
        header.version = 1
        header.type = UInt8(CSP_MSG_HELLO.rawValue)
        header.flags = 0
        header.session_id = 0
        header.sequence = sequence; sequence += 1
        header.payload_length = UInt32(payload.count)

        var msg = [UInt8](repeating: 0, count: Int(CSP_HEADER_SIZE) + payload.count)
        _ = csp_encode_header(&header, &msg, msg.count)
        msg.replaceSubrange(Int(CSP_HEADER_SIZE)..<msg.count, with: payload)

        conn.send(content: Data(msg), completion: .contentProcessed { [weak self] _ in
            self?.readHelloAck()
        })
    }

    private func readHelloAck() {
        connection?.receive(minimumIncompleteLength: Int(CSP_HEADER_SIZE + 12), maximumLength: Int(CSP_HEADER_SIZE + 12)) { [weak self] content, _, _, _ in
            guard let self = self, let data = content, data.count >= 36 else { return }

            var header = CspHeader()
            data.withUnsafeBytes { ptr in
                _ = csp_decode_header(ptr.bindMemory(to: UInt8.self).baseAddress, 24, &header)
            }

            if header.type == UInt8(CSP_MSG_HELLO_ACK.rawValue) {
                let sid = data.withUnsafeBytes { ptr -> UInt32 in
                    let p = ptr.bindMemory(to: UInt8.self).baseAddress! + 28
                    return (UInt32(p[0]) << 24) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8) | UInt32(p[3])
                }
                self.sessionId = sid
                self.onLog?("Test Sender: Received HELLO_ACK. Assigned Session ID: \(sid)")
                self.sendVideoConfig()
            }
        }
    }

    private func sendVideoConfig() {
        guard let conn = connection else { return }

        // Golden 1080p High Profile SPS + PPS Annex-B
        let spsPps: [UInt8] = [
            0x00, 0x00, 0x00, 0x01, 0x27, 0x64, 0x00, 0x28, 0xAC, 0x56, 0x50, 0x1E, 0x00, 0x89, 0xF9, 0x50,
            0x00, 0x00, 0x00, 0x01, 0x28, 0xEE, 0x3C, 0xB0
        ]


        var payload = [UInt8](repeating: 0, count: 24 + spsPps.count)
        payload[0] = 0; payload[1] = 0; payload[2] = 0; payload[3] = 1 // configId = 1
        payload[4] = 1 // codec = H264
        payload[5] = 66 // Baseline profile
        payload[6] = 40 // Level 4.0
        payload[7] = 0  // rotation = 0
        payload[8] = 0x07; payload[9] = 0x80 // 1920 width
        payload[10] = 0x04; payload[11] = 0x38 // 1080 height
        payload[12] = 0x00; payload[13] = 0x3C // 60 FPS
        payload[14] = 0; payload[15] = 0 // reserved
        payload[16] = 0x00; payload[17] = 0xB7; payload[18] = 0x1B; payload[19] = 0x00 // 12 Mbps
        payload[20] = UInt8((spsPps.count >> 24) & 0xFF)
        payload[21] = UInt8((spsPps.count >> 16) & 0xFF)
        payload[22] = UInt8((spsPps.count >> 8) & 0xFF)
        payload[23] = UInt8(spsPps.count & 0xFF)
        payload.replaceSubrange(24..<24+spsPps.count, with: spsPps)

        var header = CspHeader()
        header.version = 1
        header.type = UInt8(CSP_MSG_VIDEO_CONFIG.rawValue)
        header.flags = 0
        header.session_id = sessionId
        header.sequence = sequence; sequence += 1
        header.payload_length = UInt32(payload.count)

        var msg = [UInt8](repeating: 0, count: Int(CSP_HEADER_SIZE) + payload.count)
        _ = csp_encode_header(&header, &msg, msg.count)
        msg.replaceSubrange(Int(CSP_HEADER_SIZE)..<msg.count, with: payload)

        conn.send(content: Data(msg), completion: .contentProcessed { [weak self] _ in
            self?.onLog?("Test Sender: VIDEO_CONFIG sent. Starting 60 FPS frame stream...")
            self?.startFrameStream()
        })
    }

    private func startFrameStream() {
        self.isStreaming = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.sendNextFrame()
            }
        }
    }

    private func sendNextFrame() {
        guard let conn = connection, isStreaming else { return }

        frameCount += 1
        let isKeyframe = (frameCount % 60 == 1) // Keyframe every 1s
        let ptsMicros = UInt64(Date().timeIntervalSince1970 * 1_000_000)

        // Dummy slice NALU with start code
        let sliceNalu: [UInt8] = isKeyframe ?
            [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x00, 0x10, 0xFF] :
            [0x00, 0x00, 0x00, 0x01, 0x41, 0x9A, 0x02, 0x03, 0x04]

        var prefix = [UInt8](repeating: 0, count: 16)
        _ = csp_encode_video_frame_prefix(1, isKeyframe ? UInt32(CSP_FRAME_KEYFRAME) : 0, ptsMicros, &prefix, 16)

        let totalPayloadLen = prefix.count + sliceNalu.count
        var header = CspHeader()
        header.version = 1
        header.type = UInt8(CSP_MSG_VIDEO_FRAME.rawValue)
        header.flags = 0
        header.session_id = sessionId
        header.sequence = sequence; sequence += 1
        header.payload_length = UInt32(totalPayloadLen)

        var msg = [UInt8](repeating: 0, count: Int(CSP_HEADER_SIZE) + totalPayloadLen)
        _ = csp_encode_header(&header, &msg, msg.count)
        msg.replaceSubrange(Int(CSP_HEADER_SIZE)..<Int(CSP_HEADER_SIZE)+16, with: prefix)
        msg.replaceSubrange(Int(CSP_HEADER_SIZE)+16..<msg.count, with: sliceNalu)

        conn.send(content: Data(msg), completion: .idempotent)
    }
}
