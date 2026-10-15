// ADBDeviceManager.swift — Native Event-Driven ADB Transport and Device Manager for macOS
import Foundation
import Network

public struct AndroidDevice: Identifiable, Hashable {
    public let id: String        // serial e.g. "emulator-5554" or "RF8N123..."
    public let model: String     // e.g. "Pixel 8" or "Galaxy S23"
    public let state: String     // "device", "unauthorized", "offline"

    public var isAuthorized: Bool {
        state == "device"
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: AndroidDevice, rhs: AndroidDevice) -> Bool {
        lhs.id == rhs.id && lhs.state == rhs.state && lhs.model == rhs.model
    }
}

public protocol ADBDeviceManagerDelegate: AnyObject {
    func adbDevicesDidChange(_ devices: [AndroidDevice])
}

public final class ADBDeviceManager: NSObject {
    static let commandTimeout: TimeInterval = 8.0
    public static let shared = ADBDeviceManager()

    public weak var delegate: ADBDeviceManagerDelegate?
    private let scanQueue = DispatchQueue(label: "com.castsprint.mac.adb.scan", qos: .utility)
    private var isScanning = false
    private var trackConnection: NWConnection?
    private var reconnectTimer: DispatchSourceTimer?
    private var isMonitoring = false

    public private(set) var adbPath: String?
    public private(set) var connectedDevices: [AndroidDevice] = []

    public override init() {
        super.init()
        self.adbPath = locateADB()
    }

    public func startMonitoring(interval: TimeInterval = 3.0) {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Initial one-shot scan
        refreshDevices()

        // Start event-driven socket tracking on ADB server port 5037
        startSocketTracking()
    }

    public func stopMonitoring() {
        isMonitoring = false
        stopSocketTracking()
    }

    private func stopSocketTracking() {
        reconnectTimer?.cancel()
        reconnectTimer = nil

        trackConnection?.cancel()
        trackConnection = nil
    }

    private func startSocketTracking() {
        guard isMonitoring else { return }
        stopSocketTracking()

        guard let _ = adbPath ?? locateADB() else {
            scheduleReconnect(after: 10.0)
            return
        }

        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 5037)
        let connection = NWConnection(to: endpoint, using: .tcp)
        self.trackConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.sendTrackDevicesCommand(connection: connection)
            case .failed, .cancelled:
                if self.isMonitoring {
                    self.scheduleReconnect(after: 10.0)
                }
            default:
                break
            }
        }

        connection.start(queue: scanQueue)
    }

    private func scheduleReconnect(after seconds: Double) {
        reconnectTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: scanQueue)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isMonitoring else { return }
            self.startSocketTracking()
        }
        timer.resume()
        self.reconnectTimer = timer
    }

    private func sendTrackDevicesCommand(connection: NWConnection) {
        let command = "0012host:track-devices"
        guard let data = command.data(using: .utf8) else { return }

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                NSLog("CastSprint ADB: Failed to send track-devices: %@", error.localizedDescription)
                connection.cancel()
                return
            }
            // Read 4-byte response (expecting "OKAY")
            self?.readInitialResponse(connection: connection)
        })
    }

    private func readInitialResponse(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let data = content, let str = String(data: data, encoding: .utf8), str == "OKAY" {
                // Handshake success! Now stream updates indefinitely.
                self.readNextUpdateLength(connection: connection)
            } else {
                // If ADB server returned FAIL or closed, fall back to reconnect
                connection.cancel()
            }
        }
    }

    private func readNextUpdateLength(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            guard let data = content, data.count == 4,
                  let hexStr = String(data: data, encoding: .utf8),
                  let length = Int(hexStr, radix: 16) else {
                if !isComplete {
                    connection.cancel()
                }
                return
            }

            if length == 0 {
                // Empty list of devices
                DispatchQueue.main.async {
                    if !self.connectedDevices.isEmpty {
                        self.connectedDevices = []
                        self.delegate?.adbDevicesDidChange([])
                    }
                }
                self.readNextUpdateLength(connection: connection)
            } else {
                self.readUpdatePayload(connection: connection, length: length)
            }
        }
    }

    private func readUpdatePayload(connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            guard let data = content, let payloadStr = String(data: data, encoding: .utf8) else {
                if !isComplete {
                    connection.cancel()
                }
                return
            }

            let parsed = self.parseTrackDevicesOutput(payloadStr)
            DispatchQueue.main.async {
                if self.connectedDevices != parsed {
                    self.connectedDevices = parsed
                    self.delegate?.adbDevicesDidChange(parsed)
                }
            }

            // Loop to wait for the next asynchronous device event
            self.readNextUpdateLength(connection: connection)
        }
    }

    private func parseTrackDevicesOutput(_ output: String) -> [AndroidDevice] {
        var result: [AndroidDevice] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let serial = parts[0]
            let state = parts[1]
            var model = "Android Device"

            if let existing = self.connectedDevices.first(where: { $0.id == serial }), !existing.model.isEmpty {
                model = existing.model
            }

            result.append(AndroidDevice(id: serial, model: model, state: state))
        }
        return result
    }

    public func locateADB() -> String? {
        let candidatePaths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk/platform-tools/adb").path,
            "/usr/bin/adb"
        ]

        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    public func refreshDevices() {
        guard let adb = adbPath ?? locateADB() else {
            return
        }
        self.adbPath = adb

        scanQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isScanning else { return }
            self.isScanning = true

            let output = self.runCommand(adb, arguments: ["devices", "-l"])
            let parsed = self.parseDeviceList(output)

            DispatchQueue.main.async {
                self.isScanning = false
                if self.connectedDevices != parsed {
                    self.connectedDevices = parsed
                    self.delegate?.adbDevicesDidChange(parsed)
                }
            }
        }
    }

    /// Configures ADB reverse port forwarding so Android connects to Mac receiver
    public func setupReversePortForward(serial: String, port: UInt16 = 27183) -> Bool {
        guard let adb = adbPath else { return false }
        let result = runCommand(adb, arguments: ["-s", serial, "reverse", "tcp:\(port)", "tcp:\(port)"])
        NSLog("CastSprint ADB: setupReversePortForward on %@ -> %@", serial, result)
        return true
    }

    /// Removes ADB reverse port forwarding upon session disconnect
    public func removeReversePortForward(serial: String, port: UInt16 = 27183) {
        guard let adb = adbPath else { return }
        _ = runCommand(adb, arguments: ["-s", serial, "reverse", "--remove", "tcp:\(port)"])
        NSLog("CastSprint ADB: removed reverse port forward on %@", serial)
    }

    /// Automatically launches the CastSprint Android app on the device
    public func launchAndroidApp(serial: String) {
        guard let adb = adbPath else { return }
        _ = runCommand(adb, arguments: [
            "-s", serial, "shell", "am", "start", "-n", "com.castsprint.android/.MainActivity"
        ])
    }

    /// Pairs an Android 11+ device using Wireless Debugging pairing code
    public func pairWirelessDevice(host: String, port: UInt16, code: String) -> (success: Bool, message: String) {
        guard let adb = adbPath ?? locateADB() else {
            return (false, "ADB not found")
        }
        let output = runCommand(adb, arguments: ["pair", "\(host):\(port)", code])
        if output.contains("Successfully paired") {
            return (true, output)
        } else {
            return (false, output.isEmpty ? "Pairing failed" : output)
        }
    }

    public func pairWirelessDevice(
        host: String,
        port: UInt16,
        code: String,
        completion: @escaping ((success: Bool, message: String)) -> Void
    ) {
        scanQueue.async { [weak self] in
            let result = self?.pairWirelessDevice(host: host, port: port, code: code)
                ?? (false, "ADB manager unavailable")
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Connects to a previously paired Wireless Debugging target
    public func connectWirelessDevice(host: String, port: UInt16) -> (success: Bool, message: String) {
        guard let adb = adbPath ?? locateADB() else {
            return (false, "ADB not found")
        }
        let output = runCommand(adb, arguments: ["connect", "\(host):\(port)"])
        if output.contains("connected to") {
            refreshDevices()
            return (true, output)
        } else {
            return (false, output.isEmpty ? "Connection failed" : output)
        }
    }

    public func connectWirelessDevice(
        host: String,
        port: UInt16,
        completion: @escaping ((success: Bool, message: String)) -> Void
    ) {
        scanQueue.async { [weak self] in
            let result = self?.connectWirelessDevice(host: host, port: port)
                ?? (false, "ADB manager unavailable")
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Disconnects a Wireless Debugging target
    public func disconnectWirelessDevice(host: String, port: UInt16) -> Bool {
        guard let adb = adbPath ?? locateADB() else { return false }
        _ = runCommand(adb, arguments: ["disconnect", "\(host):\(port)"])
        refreshDevices()
        return true
    }

    private func parseDeviceList(_ output: String) -> [AndroidDevice] {
        var result: [AndroidDevice] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.starts(with: "List of devices") || trimmed.starts(with: "*") {
                continue
            }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let serial = parts[0]
            let state = parts[1]

            var model = "Android Device"
            for part in parts {
                if part.starts(with: "model:") {
                    model = part.replacingOccurrences(of: "model:", with: "").replacingOccurrences(of: "_", with: " ")
                }
            }

            result.append(AndroidDevice(id: serial, model: model, state: state))
        }
        return result
    }

    @discardableResult
    private func runCommand(_ command: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            let completed = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in completed.signal() }
            try process.run()
            if completed.wait(timeout: .now() + Self.commandTimeout) == .timedOut {
                process.terminate()
                if completed.wait(timeout: .now() + 1.0) == .timedOut {
                    process.interrupt()
                }
                return "ADB command timed out after \(Int(Self.commandTimeout)) seconds"
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}
