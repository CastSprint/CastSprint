// UnifiedDevice.swift — Cross-Platform Unified Device Model for macOS
import Foundation
import AVFoundation

public enum DevicePlatform: String, CaseIterable, Identifiable {
    case ios = "iOS"
    case android = "Android"

    public var id: String { rawValue }
}

public enum DeviceTransportType: String, CaseIterable, Identifiable {
    case usb = "USB"
    case wifi = "Wi-Fi (LAN)"

    public var id: String { rawValue }
}

public enum UnifiedDeviceStatus: String {
    case ready = "Ready"
    case active = "Mirroring"
    case unauthorized = "Unauthorized (ADB)"
    case busy = "Busy"
    case offline = "Offline"
}

public struct UnifiedDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let model: String
    public let platform: DevicePlatform
    public let transport: DeviceTransportType
    public var status: UnifiedDeviceStatus
    public let videoCapability: String
    public let audioAvailable: Bool
    public let isTestDevice: Bool

    public let avDevice: AVCaptureDevice?
    public let adbSerial: String?

    public init(
        id: String,
        name: String,
        model: String,
        platform: DevicePlatform,
        transport: DeviceTransportType,
        status: UnifiedDeviceStatus = .ready,
        videoCapability: String = "H.264 1080p60",
        audioAvailable: Bool = true,
        isTestDevice: Bool = false,
        avDevice: AVCaptureDevice? = nil,
        adbSerial: String? = nil
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.platform = platform
        self.transport = transport
        self.status = status
        self.videoCapability = videoCapability
        self.audioAvailable = audioAvailable
        self.isTestDevice = isTestDevice
        self.avDevice = avDevice
        self.adbSerial = adbSerial
    }

    public var systemIcon: String {
        if isTestDevice { return "testtube.2" }
        switch (platform, transport) {
        case (.ios, .usb): return "iphone"
        case (.ios, .wifi): return "wifi"
        case (.android, .usb): return "cable.connector"
        case (.android, .wifi): return "wifi"
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(transport)
    }

    public static func == (lhs: UnifiedDevice, rhs: UnifiedDevice) -> Bool {
        lhs.id == rhs.id && lhs.transport == rhs.transport && lhs.status == rhs.status && lhs.name == rhs.name
    }
}

