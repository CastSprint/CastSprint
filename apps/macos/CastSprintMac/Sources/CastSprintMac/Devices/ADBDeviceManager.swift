// ADBDeviceManager.swift — Native ADB Transport and Device Manager for macOS
import Foundation

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
        lhs.id == rhs.id
    }
}

public protocol ADBDeviceManagerDelegate: AnyObject {
    func adbDevicesDidChange(_ devices: [AndroidDevice])
}

public final class ADBDeviceManager: NSObject {
    public static let shared = ADBDeviceManager()

    public weak var delegate: ADBDeviceManagerDelegate?
    private var timer: Timer?

    public private(set) var adbPath: String?
    public private(set) var connectedDevices: [AndroidDevice] = []

    public override init() {
        super.init()
        self.adbPath = locateADB()
    }

    public func startMonitoring(interval: TimeInterval = 2.0) {
        stopMonitoring()
        refreshDevices()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
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
        guard let adb = adbPath else {
            self.adbPath = locateADB()
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let output = self?.runCommand(adb, arguments: ["devices", "-l"]) ?? ""
            let parsed = self?.parseDeviceList(output) ?? []

            DispatchQueue.main.async {
                self?.connectedDevices = parsed
                self?.delegate?.adbDevicesDidChange(parsed)
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
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }
}
