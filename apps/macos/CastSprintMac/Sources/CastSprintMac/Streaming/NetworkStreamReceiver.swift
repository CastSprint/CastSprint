// NetworkStreamReceiver.swift — Native Network.framework Receiver for CastSprint Protocol v1
import Foundation
import Network
import CCastSprintProtocol

public final class NetworkStreamReceiver {
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let queue = DispatchQueue(label: "com.castsprint.mac.network", qos: .userInteractive)

    public weak var videoSink: EncodedVideoInput?
    public weak var audioSink: AudioInput?

    private(set) public var isListening = false

    public init() {}

    public func start(port: UInt16 = 27183) throws {
        stop()

        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "CastSprint", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // TCP_NODELAY

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        let listener = try NWListener(using: params, on: portEndpoint)

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("CastSprint: Network listener ready on port %d", port)
            case .failed(let error):
                NSLog("CastSprint: Network listener failed: %@", error.localizedDescription)
                self?.stop()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener.start(queue: queue)
        self.listener = listener
        self.isListening = true
    }

    public func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
        isListening = false
    }

    private func handleNewConnection(_ connection: NWConnection) {
        if activeConnection != nil {
            // Already streaming a session; reject secondary connection
            connection.cancel()
            return
        }

        self.activeConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("CastSprint: Network client connected")
                self?.readHeader(from: connection)
            case .failed(let err):
                NSLog("CastSprint: Connection failed: %@", err.localizedDescription)
                self?.activeConnection = nil
            case .cancelled:
                self?.activeConnection = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func readHeader(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: Int(CSP_HEADER_SIZE), maximumLength: Int(CSP_HEADER_SIZE)) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, data.count == CSP_HEADER_SIZE else {
                if isComplete || error != nil {
                    self?.activeConnection = nil
                }
                return
            }

            var header = CspHeader()
            let decodeRes = data.withUnsafeBytes { rawPtr in
                csp_decode_header(rawPtr.bindMemory(to: UInt8.self).baseAddress, data.count, &header)
            }

            if decodeRes != CSP_DECODE_OK {
                NSLog("CastSprint: Protocol header decode error: %s", csp_decode_result_string(decodeRes))
                connection.cancel()
                self.activeConnection = nil
                return
            }

            // Read payload
            let payloadLen = Int(header.payload_length)
            if payloadLen > 0 {
                self.readPayload(from: connection, header: header, length: payloadLen)
            } else {
                self.readHeader(from: connection)
            }
        }
    }

    private func readPayload(from connection: NWConnection, header: CspHeader, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] content, _, _, error in
            guard let self = self, let data = content, data.count == length else {
                if error != nil { self?.activeConnection = nil }
                return
            }

            // Dispatch message payload based on header type
            switch header.type {
            case UInt8(CSP_MSG_HEARTBEAT.rawValue):
                var ts: UInt64 = 0
                var echo: UInt64 = 0
                data.withUnsafeBytes { ptr in
                    _ = csp_decode_heartbeat_payload(ptr.bindMemory(to: UInt8.self).baseAddress, data.count, &ts, &echo)
                }
                // Echo heartbeat back
                self.sendHeartbeatEcho(to: connection, session: header.session_id, seq: header.sequence + 1, echoTs: ts)

            case UInt8(CSP_MSG_VIDEO_FRAME.rawValue):
                var configId: UInt32 = 0
                var flags: UInt32 = 0
                var pts: UInt64 = 0
                var dataOffset: size_t = 0
                let ok = data.withUnsafeBytes { ptr in
                    csp_decode_video_frame_prefix(ptr.bindMemory(to: UInt8.self).baseAddress, data.count, &configId, &flags, &pts, &dataOffset)
                }
                if ok && data.count > Int(dataOffset) {
                    let framePayload = data.subdata(in: Int(dataOffset)..<data.count)
                    let frame = VideoFrameData(configId: configId, flags: flags, ptsMicros: pts, payload: framePayload)
                    self.videoSink?.onVideoFrame(frame)
                    LatencyTracker.shared.recordFrameReceived()
                }

            default:
                break
            }

            // Continue reading next message
            self.readHeader(from: connection)
        }
    }

    private func sendHeartbeatEcho(to connection: NWConnection, session: UInt32, seq: UInt32, echoTs: UInt64) {
        var buf = [UInt8](repeating: 0, count: 40)
        let nowMicros = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        let written = buf.withUnsafeMutableBytes { ptr in
            csp_encode_heartbeat_message(session, seq, nowMicros, echoTs, ptr.bindMemory(to: UInt8.self).baseAddress, ptr.count)
        }
        if written > 0 {
            connection.send(content: Data(buf), completion: .idempotent)
        }
    }
}
