// PlatformCapabilities.swift — Platform Capability Gating for CastSprint
import Foundation

public enum ConnectionMode: String, CaseIterable, Identifiable {
    case iphoneUsb = "iPhone USB (Direct)"
    case androidUsb = "Android USB (ADB)"
    case iphoneWifi = "iPhone Wi-Fi (LAN)"
    case androidWifi = "Android Wi-Fi (LAN)"
    case iphoneWindowsUsb = "iPhone USB (Windows)"

    public var id: String { rawValue }

    public var requiresCompanionApp: Bool {
        switch self {
        case .iphoneUsb:
            return false // Driverless / Zero companion app!
        case .androidUsb, .iphoneWifi, .androidWifi, .iphoneWindowsUsb:
            return true
        }
    }
}

public struct PlatformCapabilities {
    public static var current: PlatformCapabilities {
        #if os(macOS)
        return PlatformCapabilities(
            platformName: "macOS",
            supportsIPhoneUsb: true,          // CoreMediaIO + AVFoundation (No App needed)
            supportsAndroidUsb: true,         // via adb reverse
            supportsIPhoneWifi: true,         // CastSprint iOS Sender
            supportsAndroidWifi: true,        // CastSprint Android Sender
            supportsMetalRendering: true,
            supportsD3D11Rendering: false,
            supportsCoreAudio: true,
            supportsWasapi: false
        )
        #elseif os(Windows)
        return PlatformCapabilities(
            platformName: "Windows",
            supportsIPhoneUsb: false,         // Under Feasibility Study
            supportsAndroidUsb: true,
            supportsIPhoneWifi: true,
            supportsAndroidWifi: true,
            supportsMetalRendering: false,
            supportsD3D11Rendering: true,
            supportsCoreAudio: false,
            supportsWasapi: true
        )
        #else
        return PlatformCapabilities(
            platformName: "Generic",
            supportsIPhoneUsb: false,
            supportsAndroidUsb: false,
            supportsIPhoneWifi: false,
            supportsAndroidWifi: false,
            supportsMetalRendering: false,
            supportsD3D11Rendering: false,
            supportsCoreAudio: false,
            supportsWasapi: false
        )
        #endif
    }

    public let platformName: String
    public let supportsIPhoneUsb: Bool
    public let supportsAndroidUsb: Bool
    public let supportsIPhoneWifi: Bool
    public let supportsAndroidWifi: Bool
    public let supportsMetalRendering: Bool
    public let supportsD3D11Rendering: Bool
    public let supportsCoreAudio: Bool
    public let supportsWasapi: Bool

    public func isModeSupported(_ mode: ConnectionMode) -> Bool {
        switch mode {
        case .iphoneUsb: return supportsIPhoneUsb
        case .androidUsb: return supportsAndroidUsb
        case .iphoneWifi: return supportsIPhoneWifi
        case .androidWifi: return supportsAndroidWifi
        case .iphoneWindowsUsb: return false // Explicitly gated as unsupported
        }
    }
}
