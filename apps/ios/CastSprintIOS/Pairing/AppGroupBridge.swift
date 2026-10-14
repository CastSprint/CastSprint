// AppGroupBridge.swift — IPC & Configuration Sharing between App & Broadcast Extension
import Foundation

public struct StreamConfiguration: Codable, Equatable {
    public var receiverHost: String
    public var receiverPort: UInt16
    public var pairingPin: String
    public var targetWidth: Int32
    public var targetHeight: Int32
    public var targetFps: Int32
    public var targetBitrateBps: Int32
    public var isAudioEnabled: Bool
    public var isMicrophoneEnabled: Bool
    public var receiverName: String

    public init(
        receiverHost: String = "",
        receiverPort: UInt16 = 27183,
        pairingPin: String = "",
        targetWidth: Int32 = 1920,
        targetHeight: Int32 = 1080,
        targetFps: Int32 = 60,
        targetBitrateBps: Int32 = 12_000_000,
        isAudioEnabled: Bool = true,
        isMicrophoneEnabled: Bool = false,
        receiverName: String = ""
    ) {
        self.receiverHost = receiverHost
        self.receiverPort = receiverPort
        self.pairingPin = pairingPin
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
        self.targetFps = targetFps
        self.targetBitrateBps = targetBitrateBps
        self.isAudioEnabled = isAudioEnabled
        self.isMicrophoneEnabled = isMicrophoneEnabled
        self.receiverName = receiverName
    }
}

public struct DiscoveredReceiver: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let host: String
    public let port: UInt16
    public let platform: String
    public let pin: String?

    public init(name: String, host: String, port: UInt16, platform: String, pin: String? = nil) {
        self.id = "\(host):\(port)"
        self.name = name
        self.host = host
        self.port = port
        self.platform = platform
        self.pin = pin
    }
}

public final class AppGroupBridge {
    public static let shared = AppGroupBridge()
    public static let appGroupId = "group.com.castsprint.ios"

    private let defaults: UserDefaults?

    public init() {
        self.defaults = UserDefaults(suiteName: AppGroupBridge.appGroupId) ?? UserDefaults.standard
    }

    public func saveConfiguration(_ config: StreamConfiguration) {
        if let encoded = try? JSONEncoder().encode(config) {
            defaults?.set(encoded, forKey: "castsprint_stream_config")
            defaults?.synchronize()
        }
    }

    public func loadConfiguration() -> StreamConfiguration {
        guard let data = defaults?.data(forKey: "castsprint_stream_config"),
              let config = try? JSONDecoder().decode(StreamConfiguration.self, from: data) else {
            return StreamConfiguration()
        }
        return config
    }

    public func updateBroadcastState(_ state: String, error: String? = nil) {
        defaults?.set(state, forKey: "castsprint_broadcast_state")
        defaults?.set(error, forKey: "castsprint_broadcast_error")
        defaults?.set(Date().timeIntervalSince1970, forKey: "castsprint_broadcast_timestamp")
        defaults?.synchronize()
    }

    public func readBroadcastState() -> (state: String, error: String?, timestamp: Double) {
        let state = defaults?.string(forKey: "castsprint_broadcast_state") ?? "idle"
        let error = defaults?.string(forKey: "castsprint_broadcast_error")
        let timestamp = defaults?.double(forKey: "castsprint_broadcast_timestamp") ?? 0
        return (state, error, timestamp)
    }

    // MARK: - Trusted Devices

    public func getTrustedDevices() -> [DiscoveredReceiver] {
        guard let data = defaults?.data(forKey: "castsprint_trusted_devices"),
              let rawList = try? JSONDecoder().decode([SavedReceiver].self, from: data) else {
            return []
        }
        return rawList.map { DiscoveredReceiver(name: $0.name, host: $0.host, port: $0.port, platform: $0.platform) }
    }

    public func addTrustedDevice(_ device: DiscoveredReceiver) {
        var current = getTrustedDevices().filter { $0.id != device.id }
        current.append(device)
        let list = current.map { SavedReceiver(name: $0.name, host: $0.host, port: $0.port, platform: $0.platform) }
        if let encoded = try? JSONEncoder().encode(list) {
            defaults?.set(encoded, forKey: "castsprint_trusted_devices")
            defaults?.synchronize()
        }
    }

    public func removeTrustedDevice(id: String) {
        let current = getTrustedDevices().filter { $0.id != id }
        let list = current.map { SavedReceiver(name: $0.name, host: $0.host, port: $0.port, platform: $0.platform) }
        if let encoded = try? JSONEncoder().encode(list) {
            defaults?.set(encoded, forKey: "castsprint_trusted_devices")
            defaults?.synchronize()
        }
    }
}

private struct SavedReceiver: Codable {
    let name: String
    let host: String
    let port: UInt16
    let platform: String
}
