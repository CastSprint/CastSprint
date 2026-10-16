// NetworkTransportSink.swift — High-Performance Low-Latency TCP Transport for CastSprint
import Foundation
import Network

public enum TransportError: Error, LocalizedError {
    case connectionFailed(String)
    case handshakeFailed(String)
    case disconnected
    case timeout

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .disconnected: return "Stream disconnected"
        case .timeout: return "Connection timed out"
        }
    }
}

public protocol NetworkTransportDelegate: AnyObject {
    func transportDidConnect(_ transport: NetworkTransportSink, helloAck: ProtocolCodec.HelloAck)
    func transportDidDisconnect(_ transport: NetworkTransportSink, error: Error?)
    func transportMetricsUpdated(_ transport: NetworkTransportSink, bitrateMbps: Double, rttMs: Double)
}

public final class NetworkTransportSink {
    public weak var delegate: NetworkTransportDelegate?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.castsprint.ios.network", qos: .userInteractive)
    private var sequence: UInt32 = 0
    private var sessionId: UInt32 = 0
    private var heartbeatTimer: DispatchSourceTimer?

    private var bytesSentWindow: UInt64 = 0
    private var lastMetricsTimestamp: Date = Date()
    private var lastEchoTimestampUs: UInt64 = 0
    public private(set) var currentRttMs: Double = 0.0
    public private(set) var currentBitrateMbps: Double = 0.0

    public private(set) var isConnected: Bool = false
    public private(set) var isStreaming: Bool = false

    public init() {}

    public func connect(
        host: String,
        port: UInt16 = ProtocolV1Constants.defaultPort,
        pairingToken: String,
        deviceName: String = "iPhone",
        deviceModel: String = "iOS Device",
        width: UInt16 = 1920,
        height: UInt16 = 1080,
        fps: UInt16 = 60,
        completion: @escaping (Result<ProtocolCodec.HelloAck, Error>) -> Void
    ) {
        disconnect()

        guard pairingToken.count == 6, pairingToken.allSatisfy(\.isNumber) else {
            completion(.failure(TransportError.handshakeFailed("A six-digit pairing token is required")))
            return
        }

        let hostEndpoint = NWEndpoint.Host(host)
        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            completion(.failure(TransportError.connectionFailed("Invalid port: \(port)")))
            return
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // Enable TCP_NODELAY for sub-frame latency
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        let conn = NWConnection(host: hostEndpoint, port: portEndpoint, using: params)
        self.connection = conn

        var didComplete = false

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.isConnected = true
                self.sendHello(
                    deviceName: deviceName,
                    pairingToken: pairingToken,
                    deviceModel: deviceModel,
                    width: width,
                    height: height,
                    fps: fps
                ) { result in
                    if !didComplete {
                        didComplete = true
                        switch result {
                        case .success(let ack):
                            self.sessionId = ack.sessionId
                            self.isStreaming = true
                            self.startHeartbeat()
                            self.startReceiveLoop()
                            self.delegate?.transportDidConnect(self, helloAck: ack)
                            completion(.success(ack))
                        case .failure(let err):
                            self.disconnect()
                            completion(.failure(err))
                        }
                    }
                }

            case .failed(let error):
                self.isConnected = false
                self.isStreaming = false
                if !didComplete {
                    didComplete = true
                    completion(.failure(TransportError.connectionFailed(error.localizedDescription)))
                } else {
                    self.delegate?.transportDidDisconnect(self, error: error)
                }

            case .cancelled:
                self.isConnected = false
                self.isStreaming = false
                if !didComplete {
                    didComplete = true
                    completion(.failure(TransportError.disconnected))
                } else {
                    self.delegate?.transportDidDisconnect(self, error: nil)
                }

            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    public func disconnect(reason: UInt16 = 1, message: String = "User requested disconnect") {
        if isStreaming {
            let payload = ProtocolCodec.disconnectPayload(reason: reason, message: message)
            let msg = ProtocolCodec.encodeMessage(type: .disconnect, sessionId: sessionId, sequence: nextSequence(), payload: payload)
            connection?.send(content: msg, completion: .idempotent)
        }

        stopHeartbeat()
        connection?.cancel()
        connection = nil
        isConnected = false
        isStreaming = false
        sessionId = 0
        sequence = 0
        bytesSentWindow = 0
        currentRttMs = 0
        currentBitrateMbps = 0
    }

    // MARK: - Handshake & Receive Loop

    private func sendHello(
        deviceName: String,
        pairingToken: String,
        deviceModel: String,
        width: UInt16,
        height: UInt16,
        fps: UInt16,
        completion: @escaping (Result<ProtocolCodec.HelloAck, Error>) -> Void
    ) {
        guard let conn = connection else {
            completion(.failure(TransportError.disconnected))
            return
        }

        let caps = ProtocolV1Constants.capVideoH264 | ProtocolV1Constants.capAudio | ProtocolV1Constants.capPlatformIOS
        let helloPayload = ProtocolCodec.helloPayload(
            capabilities: caps,
            osVersion: 18,
            width: width,
            height: height,
            densityDpi: 460,
            deviceName: "\(deviceName)|\(pairingToken)",
            deviceModel: deviceModel
        )

        let helloMsg = ProtocolCodec.encodeMessage(
            type: .hello,
            sessionId: 0,
            sequence: nextSequence(),
            payload: helloPayload
        )

        conn.send(content: helloMsg, completion: .contentProcessed { [weak self] sendErr in
            if let sendErr = sendErr {
                completion(.failure(TransportError.handshakeFailed("Failed to send HELLO: \(sendErr)")))
                return
            }

            self?.receiveHelloAck(completion: completion)
        })
    }

    private func receiveHelloAck(completion: @escaping (Result<ProtocolCodec.HelloAck, Error>) -> Void) {
        guard let conn = connection else {
            completion(.failure(TransportError.disconnected))
            return
        }

        conn.receive(minimumIncompleteLength: ProtocolV1Constants.headerSize, maximumLength: ProtocolV1Constants.headerSize) { data, context, isComplete, error in
            if let error = error {
                completion(.failure(TransportError.handshakeFailed("Error reading HELLO_ACK header: \(error)")))
                return
            }
            guard let headerData = data, headerData.count == ProtocolV1Constants.headerSize else {
                completion(.failure(TransportError.handshakeFailed("Incomplete header for HELLO_ACK")))
                return
            }

            let result = ProtocolCodec.decodeHeader(headerData)
            switch result {
            case .ok(let hdr):
                guard hdr.type == .helloAck else {
                    completion(.failure(TransportError.handshakeFailed("Expected HELLO_ACK (0x02), got \(hdr.type)")))
                    return
                }

                let payloadLen = Int(hdr.payloadLength)
                conn.receive(minimumIncompleteLength: payloadLen, maximumLength: payloadLen) { pData, _, _, pErr in
                    if let pErr = pErr {
                        completion(.failure(TransportError.handshakeFailed("Error reading HELLO_ACK payload: \(pErr)")))
                        return
                    }
                    guard let payload = pData, let ack = ProtocolCodec.decodeHelloAck(payload) else {
                        completion(.failure(TransportError.handshakeFailed("Invalid HELLO_ACK payload")))
                        return
                    }
                    guard ack.status == 0 else {
                        completion(.failure(TransportError.handshakeFailed("Receiver rejected connection with status \(ack.status)")))
                        return
                    }

                    completion(.success(ack))
                }

            case .invalid(let reason):
                completion(.failure(TransportError.handshakeFailed("Header decode invalid: \(reason)")))
            case .needMoreData:
                completion(.failure(TransportError.handshakeFailed("Truncated header")))
            }
        }
    }

    private func startReceiveLoop() {
        guard let conn = connection, isConnected else { return }

        conn.receive(minimumIncompleteLength: ProtocolV1Constants.headerSize, maximumLength: ProtocolV1Constants.headerSize) { [weak self] data, _, isComplete, err in
            guard let self = self, self.isConnected else { return }
            if isComplete || err != nil {
                self.delegate?.transportDidDisconnect(self, error: err)
                return
            }
            guard let headerData = data, case .ok(let hdr) = ProtocolCodec.decodeHeader(headerData) else {
                self.startReceiveLoop()
                return
            }

            let payloadLen = Int(hdr.payloadLength)
            if payloadLen == 0 {
                self.handleMessage(header: hdr, payload: Data())
                self.startReceiveLoop()
                return
            }

            conn.receive(minimumIncompleteLength: payloadLen, maximumLength: payloadLen) { [weak self] pData, _, _, pErr in
                guard let self = self, self.isConnected else { return }
                if let payload = pData {
                    self.handleMessage(header: hdr, payload: payload)
                }
                self.startReceiveLoop()
            }
        }
    }

    private func handleMessage(header: ProtocolHeader, payload: Data) {
        switch header.type {
        case .heartbeat:
            if payload.count >= 16 {
                let echoTs = payload.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self).bigEndian }
                if echoTs > 0 {
                    let nowUs = UInt64(Date().timeIntervalSince1970 * 1_000_000)
                    if nowUs >= echoTs {
                        let rttUs = nowUs - echoTs
                        self.currentRttMs = Double(rttUs) / 1000.0
                    }
                }
            }
        case .disconnect:
            delegate?.transportDidDisconnect(self, error: nil)
        default:
            break
        }
    }

    // MARK: - Streaming Transmission

    public func sendVideoConfig(
        configId: UInt32,
        width: UInt16,
        height: UInt16,
        fps: UInt16,
        bitrate: UInt32,
        csd: Data
    ) {
        guard let conn = connection, isStreaming else { return }

        let payload = ProtocolCodec.videoConfigPayload(
            configId: configId,
            codec: 1, // H.264
            profile: 66,
            level: 42,
            rotation: 0,
            width: width,
            height: height,
            fps: fps,
            bitrate: bitrate,
            csd: csd
        )

        let msg = ProtocolCodec.encodeMessage(
            type: .videoConfig,
            sessionId: sessionId,
            sequence: nextSequence(),
            payload: payload
        )

        recordBytesSent(msg.count)
        conn.send(content: msg, completion: .idempotent)
    }

    public func sendVideoFrame(configId: UInt32, isKeyframe: Bool, ptsMicros: UInt64, payload: Data) {
        guard let conn = connection, isStreaming else { return }

        let prefix = ProtocolCodec.videoFramePrefix(configId: configId, isKeyframe: isKeyframe, ptsUs: ptsMicros)
        let totalPayloadLen = UInt32(prefix.count + payload.count)

        let header = ProtocolHeader(
            type: .videoFrame,
            sessionId: sessionId,
            sequence: nextSequence(),
            payloadLength: totalPayloadLen
        )

        var msg = ProtocolCodec.encodeHeader(header)
        msg.append(prefix)
        msg.append(payload)

        recordBytesSent(msg.count)
        conn.send(content: msg, completion: .idempotent)
    }

    public func sendAudioConfig(channels: UInt8, sampleRate: UInt32, csd: Data) {
        guard let conn = connection, isStreaming else { return }

        let payload = ProtocolCodec.audioConfigPayload(
            codec: ProtocolV1Constants.audioCodecAAC,
            channels: channels,
            sampleRate: sampleRate,
            csd: csd
        )

        let msg = ProtocolCodec.encodeMessage(
            type: .audioConfig,
            sessionId: sessionId,
            sequence: nextSequence(),
            payload: payload
        )

        recordBytesSent(msg.count)
        conn.send(content: msg, completion: .idempotent)
    }

    public func sendAudioFrame(ptsMicros: UInt64, payload: Data) {
        guard let conn = connection, isStreaming else { return }

        let prefix = ProtocolCodec.audioFramePrefix(ptsUs: ptsMicros)
        let totalPayloadLen = UInt32(prefix.count + payload.count)

        let header = ProtocolHeader(
            type: .audioFrame,
            sessionId: sessionId,
            sequence: nextSequence(),
            payloadLength: totalPayloadLen
        )

        var msg = ProtocolCodec.encodeHeader(header)
        msg.append(prefix)
        msg.append(payload)

        recordBytesSent(msg.count)
        conn.send(content: msg, completion: .idempotent)
    }

    // MARK: - Heartbeat & Metrics

    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isStreaming, let conn = self.connection else { return }

            let nowUs = UInt64(Date().timeIntervalSince1970 * 1_000_000)
            let payload = ProtocolCodec.heartbeatPayload(timestampUs: nowUs, echoTimestampUs: self.lastEchoTimestampUs)
            let msg = ProtocolCodec.encodeMessage(
                type: .heartbeat,
                sessionId: self.sessionId,
                sequence: self.nextSequence(),
                payload: payload
            )
            conn.send(content: msg, completion: .idempotent)

            // Update Bitrate Metric
            let elapsed = Date().timeIntervalSince(self.lastMetricsTimestamp)
            if elapsed >= 1.0 {
                let bits = Double(self.bytesSentWindow) * 8.0
                self.currentBitrateMbps = (bits / elapsed) / 1_000_000.0
                self.bytesSentWindow = 0
                self.lastMetricsTimestamp = Date()
                self.delegate?.transportMetricsUpdated(self, bitrateMbps: self.currentBitrateMbps, rttMs: self.currentRttMs)
            }
        }
        timer.resume()
        self.heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func nextSequence() -> UInt32 {
        let seq = sequence
        sequence = sequence &+ 1
        return seq
    }

    private func recordBytesSent(_ count: Int) {
        bytesSentWindow &+= UInt64(count)
    }
}
