// NetworkTransportSink.swift — iOS Network Transport Sink for CastSprint Protocol v1
import Foundation
import Network

public final class NetworkTransportSink {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.castsprint.ios.network", qos: .userInteractive)
    private var sequence: UInt32 = 0
    private var sessionId: UInt32 = 0

    public private(set) var isConnected = false

    public init() {}

    public func connect(host: String, port: UInt16 = 27183, completion: @escaping (Bool) -> Void) {
        disconnect()

        let hostEndpoint = NWEndpoint.Host(host)
        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            completion(false)
            return
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // TCP_NODELAY

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        let conn = NWConnection(host: hostEndpoint, port: portEndpoint, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                completion(true)
            case .failed, .cancelled:
                self?.isConnected = false
                completion(false)
            default:
                break
            }
        }

        self.connection = conn
        conn.start(queue: queue)
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        sequence = 0
    }

    public func sendVideoFrame(configId: UInt32, isKeyframe: Bool, ptsMicros: UInt64, payload: Data) {
        guard let connection = connection, isConnected else { return }

        // 1. Prepare 24-byte header + 16-byte frame prefix
        var headerBytes = [UInt8](repeating: 0, count: 24)
        let totalPayloadLen = 16 + payload.count

        // CSPR magic (0x43535052)
        headerBytes[0] = 0x43; headerBytes[1] = 0x53; headerBytes[2] = 0x50; headerBytes[3] = 0x52
        headerBytes[4] = 1    // version
        headerBytes[5] = 0x11 // VIDEO_FRAME
        headerBytes[6] = 0; headerBytes[7] = 0 // flags

        // Session ID & sequence
        headerBytes[8] = UInt8((sessionId >> 24) & 0xFF)
        headerBytes[9] = UInt8((sessionId >> 16) & 0xFF)
        headerBytes[10] = UInt8((sessionId >> 8) & 0xFF)
        headerBytes[11] = UInt8(sessionId & 0xFF)

        sequence += 1
        headerBytes[12] = UInt8((sequence >> 24) & 0xFF)
        headerBytes[13] = UInt8((sequence >> 16) & 0xFF)
        headerBytes[14] = UInt8((sequence >> 8) & 0xFF)
        headerBytes[15] = UInt8(sequence & 0xFF)

        headerBytes[16] = UInt8((totalPayloadLen >> 24) & 0xFF)
        headerBytes[17] = UInt8((totalPayloadLen >> 16) & 0xFF)
        headerBytes[18] = UInt8((totalPayloadLen >> 8) & 0xFF)
        headerBytes[19] = UInt8(totalPayloadLen & 0xFF)

        // Frame prefix (16 bytes)
        var prefix = [UInt8](repeating: 0, count: 16)
        prefix[0] = UInt8((configId >> 24) & 0xFF)
        prefix[1] = UInt8((configId >> 16) & 0xFF)
        prefix[2] = UInt8((configId >> 8) & 0xFF)
        prefix[3] = UInt8(configId & 0xFF)

        let flags: UInt32 = isKeyframe ? 1 : 0
        prefix[4] = UInt8((flags >> 24) & 0xFF)
        prefix[5] = UInt8((flags >> 16) & 0xFF)
        prefix[6] = UInt8((flags >> 8) & 0xFF)
        prefix[7] = UInt8(flags & 0xFF)

        for i in (0..<8).reversed() {
            prefix[8 + (7 - i)] = UInt8((ptsMicros >> (i * 8)) & 0xFF)
        }

        var messageData = Data(headerBytes)
        messageData.append(contentsOf: prefix)
        messageData.append(payload)

        connection.send(content: messageData, completion: .idempotent)
    }
}
