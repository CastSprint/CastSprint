// NetworkStreamReceiver.swift — Native CastSprint Protocol v1 Network Receiver
import Foundation
import Network
import CCastSprintProtocol
import CoreVideo

public protocol NetworkStreamReceiverDelegate: AnyObject {
    func receiverDidConnectDevice(name: String, model: String, platform: String, sessionId: UInt32)
    func receiverDidReceivePixelBuffer(_ pixelBuffer: CVPixelBuffer, ptsMicros: UInt64)
    func receiverDidReceiveAudio(ptsMicros: UInt64, payload: Data)
    func receiverDidDisconnect()
    func receiverDidEncounterError(_ error: Error)
}

public final class NetworkStreamReceiver: VideoDecoderDelegate {
    public weak var delegate: NetworkStreamReceiverDelegate?

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let queue = DispatchQueue(label: "com.castsprint.mac.network.receiver", qos: .userInteractive)

    public let videoDecoder = VideoToolboxDecoder()
    private(set) public var isListening = false
    private(set) public var activeSessionId: UInt32 = 0
    private var sequenceOut: UInt32 = 0

    public init() {
        videoDecoder.delegate = self
    }

    public func start(port: UInt16 = 27183) throws {
        stop()

        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "CastSprint", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // TCP_NODELAY for sub-millisecond network delivery

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        let listener = try NWListener(using: params, on: portEndpoint)

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("CastSprint Receiver: Listening on port %d", port)
            case .failed(let error):
                NSLog("CastSprint Receiver: Listener failed: %@", error.localizedDescription)
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
        activeSessionId = 0
        sequenceOut = 0
        videoDecoder.teardown()
    }

    private func handleNewConnection(_ connection: NWConnection) {
        if activeConnection != nil {
            NSLog("CastSprint Receiver: Rejecting secondary connection; session active")
            connection.cancel()
            return
        }

        self.activeConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("CastSprint Receiver: Peer TCP established. Awaiting HELLO...")
                self?.readHeader(from: connection)
            case .failed(let err):
                NSLog("CastSprint Receiver: Connection failed: %@", err.localizedDescription)
                self?.handleDisconnect()
            case .cancelled:
                self?.handleDisconnect()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func handleDisconnect() {
        activeConnection = nil
        activeSessionId = 0
        videoDecoder.teardown()
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.receiverDidDisconnect()
        }
    }

    private func readHeader(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: Int(CSP_HEADER_SIZE), maximumLength: Int(CSP_HEADER_SIZE)) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, data.count == CSP_HEADER_SIZE else {
                if isComplete || error != nil {
                    self?.handleDisconnect()
                }
                return
            }

            var header = CspHeader()
            let decodeRes = data.withUnsafeBytes { rawPtr in
                csp_decode_header(rawPtr.bindMemory(to: UInt8.self).baseAddress, data.count, &header)
            }

            if decodeRes != CSP_DECODE_OK {
                NSLog("CastSprint Receiver: Protocol header decode error: %s", csp_decode_result_string(decodeRes))
                connection.cancel()
                self.handleDisconnect()
                return
            }

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
                if error != nil { self?.handleDisconnect() }
                return
            }

            self.processMessage(connection: connection, header: header, payload: data)
            self.readHeader(from: connection)
        }
    }

    private func processMessage(connection: NWConnection, header: CspHeader, payload: Data) {
        switch header.type {
        case UInt8(CSP_MSG_HELLO.rawValue):
            handleHello(connection: connection, header: header, payload: payload)

        case UInt8(CSP_MSG_VIDEO_CONFIG.rawValue):
            handleVideoConfig(payload: payload)

        case UInt8(CSP_MSG_VIDEO_FRAME.rawValue):
            handleVideoFrame(payload: payload)

        case UInt8(CSP_MSG_AUDIO_CONFIG.rawValue):
            handleAudioConfig(payload: payload)

        case UInt8(CSP_MSG_AUDIO_FRAME.rawValue):
            handleAudioFrame(payload: payload)

        case UInt8(CSP_MSG_HEARTBEAT.rawValue):
            handleHeartbeat(connection: connection, header: header, payload: payload)

        case UInt8(CSP_MSG_DISCONNECT.rawValue):
            NSLog("CastSprint Receiver: Peer requested disconnect")
            connection.cancel()
            handleDisconnect()

        default:
            break
        }
    }

    private func handleHello(connection: NWConnection, header: CspHeader, payload: Data) {
        var minVer: UInt8 = 0, maxVer: UInt8 = 0
        var caps: UInt32 = 0, apiLevel: UInt16 = 0
        var width: UInt16 = 0, height: UInt16 = 0, dpi: UInt16 = 0
        var nameBuf = [CChar](repeating: 0, count: 256)
        var modelBuf = [CChar](repeating: 0, count: 256)

        payload.withUnsafeBytes { ptr in
            _ = csp_decode_hello_payload(
                ptr.bindMemory(to: UInt8.self).baseAddress, payload.count,
                &minVer, &maxVer, &caps, &apiLevel, &width, &height, &dpi,
                &nameBuf, nameBuf.count, &modelBuf, modelBuf.count
            )
        }

        let devName = String(cString: nameBuf)
        let devModel = String(cString: modelBuf)
        let isIOS = (caps & UInt32(CSP_CAP_PLATFORM_IOS)) != 0 || devModel.contains("iPhone") || devModel.contains("iPad")
        let platform = isIOS ? "iOS" : "Android"

        self.activeSessionId = UInt32.random(in: 100000...999999)
        NSLog("CastSprint Receiver: HELLO from %@ (%@) [%@, %dx%d]. Assigned Session: %d", devName, devModel, platform, width, height, activeSessionId)

        // Respond with HELLO_ACK
        var ackBuf = [UInt8](repeating: 0, count: 36)
        let written = ackBuf.withUnsafeMutableBytes { ptr in
            csp_encode_hello_ack_message(
                activeSessionId, sequenceOut,
                0, // status = 0 (Accepted)
                1, // accepted_version = 1
                8 * 1024 * 1024, // 8 MiB max payload
                ptr.bindMemory(to: UInt8.self).baseAddress, ptr.count
            )

        }
        sequenceOut += 1

        if written > 0 {
            connection.send(content: Data(ackBuf[0..<written]), completion: .idempotent)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.receiverDidConnectDevice(
                name: devName.isEmpty ? devModel : devName,
                model: devModel,
                platform: platform,
                sessionId: self.activeSessionId
            )
        }
    }

    private func handleVideoConfig(payload: Data) {
        var configId: UInt32 = 0
        var codec: UInt8 = 0
        var rot: UInt8 = 0
        var width: UInt16 = 0, height: UInt16 = 0, fps: UInt16 = 0
        var bitrate: UInt32 = 0
        var csdOff: size_t = 0, csdLen: size_t = 0

        let ok = payload.withUnsafeBytes { ptr in
            csp_decode_video_config_payload(
                ptr.bindMemory(to: UInt8.self).baseAddress, payload.count,
                &configId, &codec, &rot, &width, &height, &fps, &bitrate, &csdOff, &csdLen
            )
        }

        if ok && csdLen > 0 && (csdOff + csdLen) <= payload.count {
            let csd = payload.subdata(in: Int(csdOff)..<Int(csdOff + csdLen))
            _ = videoDecoder.configureH264(configId: configId, csdAnnexB: csd, width: Int(width), height: Int(height))
            NSLog("CastSprint Receiver: VIDEO_CONFIG received (%dx%d, %d fps, csd %d bytes)", width, height, fps, csdLen)
        }
    }

    private func handleVideoFrame(payload: Data) {
        var configId: UInt32 = 0
        var flags: UInt32 = 0
        var pts: UInt64 = 0
        var dataOff: size_t = 0

        let ok = payload.withUnsafeBytes { ptr in
            csp_decode_video_frame_prefix(
                ptr.bindMemory(to: UInt8.self).baseAddress, payload.count,
                &configId, &flags, &pts, &dataOff
            )
        }

        if ok && payload.count > Int(dataOff) {
            let frameData = payload.subdata(in: Int(dataOff)..<payload.count)
            let isKeyframe = (flags & UInt32(CSP_FRAME_KEYFRAME)) != 0
            _ = videoDecoder.decode(configId: configId, isKeyframe: isKeyframe, ptsMicros: pts, annexBData: frameData)
        }
    }

    private func handleAudioConfig(payload: Data) {
        var codec: UInt8 = 0, channels: UInt8 = 0
        var sampleRate: UInt32 = 0
        var csdOff: size_t = 0, csdLen: size_t = 0

        _ = payload.withUnsafeBytes { ptr in
            csp_decode_audio_config_payload(
                ptr.bindMemory(to: UInt8.self).baseAddress, payload.count,
                &codec, &channels, &sampleRate, &csdOff, &csdLen
            )
        }
        NSLog("CastSprint Receiver: AUDIO_CONFIG received (codec %d, %d channels, %d Hz)", codec, channels, sampleRate)
    }

    private func handleAudioFrame(payload: Data) {
        var pts: UInt64 = 0
        var dataOff: size_t = 0

        let ok = payload.withUnsafeBytes { ptr in
            csp_decode_audio_frame_prefix(
                ptr.bindMemory(to: UInt8.self).baseAddress, payload.count,
                &pts, &dataOff
            )
        }

        if ok && payload.count > Int(dataOff) {
            let audioData = payload.subdata(in: Int(dataOff)..<payload.count)
            delegate?.receiverDidReceiveAudio(ptsMicros: pts, payload: audioData)
        }
    }

    private func handleHeartbeat(connection: NWConnection, header: CspHeader, payload: Data) {
        var ts: UInt64 = 0, echo: UInt64 = 0
        payload.withUnsafeBytes { ptr in
            _ = csp_decode_heartbeat_payload(ptr.bindMemory(to: UInt8.self).baseAddress, payload.count, &ts, &echo)
        }

        // Echo sender timestamp back
        var hbBuf = [UInt8](repeating: 0, count: 40)
        let nowMicros = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        let written = hbBuf.withUnsafeMutableBytes { ptr in
            csp_encode_heartbeat_message(
                header.session_id, sequenceOut,
                nowMicros, ts,
                ptr.bindMemory(to: UInt8.self).baseAddress, ptr.count
            )
        }
        sequenceOut += 1

        if written > 0 {
            connection.send(content: Data(hbBuf[0..<written]), completion: .idempotent)
        }
    }

    // MARK: - VideoDecoderDelegate
    public func didDecompressPixelBuffer(_ pixelBuffer: CVPixelBuffer, ptsMicros: UInt64) {
        delegate?.receiverDidReceivePixelBuffer(pixelBuffer, ptsMicros: ptsMicros)
    }

    public func didEncounterDecoderError(_ error: Error) {
        delegate?.receiverDidEncounterError(error)
    }
}
