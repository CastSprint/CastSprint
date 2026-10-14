// SourceAdapters.swift — Unified Source-Adapter Architecture for CastSprint macOS
import Foundation
import CoreMedia
import AVFoundation

public enum SourceAdapterType: String, CaseIterable, Identifiable {
    case androidUsb = "Android USB (ADB Reverse)"
    case androidLan = "Android Secure Wi-Fi"
    case iosLan = "iPhone Wi-Fi (CastSprint iOS App)"
    case iosUsbMac = "iPhone USB (Native CoreMediaIO)"
    case airPlayReceiver = "iPhone AirPlay (Zero App Wi-Fi)"
    case experimentalIosUsbWindows = "iPhone USB Hotspot (Windows NDIS)"

    public var id: String { rawValue }
}

public enum SourceAdapterStatus {
    case idle
    case connecting
    case streaming
    case error(String)
    case stopped
}

public protocol SourceAdapter: AnyObject {
    var type: SourceAdapterType { get }
    var name: String { get }
    var isAvailable: Bool { get }
    var isActive: Bool { get }
    var status: SourceAdapterStatus { get }
    var telemetryFps: Double { get }
    var telemetryLatencyMs: Double { get }

    func start() -> Bool
    func stop()
}

// =================================================================================================
// 1. IosUsbMacSourceAdapter — Primary macOS Apple Capture via CoreMediaIO + AVFoundation
// =================================================================================================
public final class IosUsbMacSourceAdapter: SourceAdapter {
    public let type: SourceAdapterType = .iosUsbMac
    public let name: String = "iPhone USB (Native CoreMediaIO)"
    public var isAvailable: Bool { true }
    public var isActive: Bool { coordinator?.isMirroring == true && coordinator?.selectedDevice?.transport == .usb }
    public var status: SourceAdapterStatus {
        if isActive { return .streaming }
        return .idle
    }
    public var telemetryFps: Double { coordinator?.currentFps ?? 0.0 }
    public var telemetryLatencyMs: Double { coordinator?.currentLatencyMs ?? 0.0 }

    private weak var coordinator: MirroringCoordinator?

    public init(coordinator: MirroringCoordinator) {
        self.coordinator = coordinator
    }

    public func start() -> Bool {
        guard let coordinator = coordinator, let dev = coordinator.selectedDevice, dev.platform == .ios else {
            return false
        }
        coordinator.startMirroring()
        return true
    }

    public func stop() {
        coordinator?.stopMirroring()
    }
}

// =================================================================================================
// 2. AndroidUsbSourceAdapter — Manages ADB reverse tunnel + local socket receiver on macOS
// =================================================================================================
public final class AndroidUsbSourceAdapter: SourceAdapter {
    public let type: SourceAdapterType = .androidUsb
    public let name: String = "Android USB (ADB Reverse)"
    public var isAvailable: Bool { true }
    public var isActive: Bool { coordinator?.isMirroring == true && coordinator?.selectedDevice?.platform == .android }
    public var status: SourceAdapterStatus {
        if isActive { return .streaming }
        return .idle
    }
    public var telemetryFps: Double { coordinator?.currentFps ?? 0.0 }
    public var telemetryLatencyMs: Double { coordinator?.currentLatencyMs ?? 0.0 }

    private weak var coordinator: MirroringCoordinator?

    public init(coordinator: MirroringCoordinator) {
        self.coordinator = coordinator
    }

    public func start() -> Bool {
        guard let coordinator = coordinator, let dev = coordinator.selectedDevice, dev.platform == .android else {
            return false
        }
        coordinator.startMirroring()
        return true
    }

    public func stop() {
        coordinator?.stopMirroring()
    }
}

// =================================================================================================
// 3. AndroidLanSourceAdapter — Manages Bonjour discovery + local network receiver on macOS
// =================================================================================================
public final class AndroidLanSourceAdapter: SourceAdapter {
    public let type: SourceAdapterType = .androidLan
    public let name: String = "Android Secure Wi-Fi"
    public var isAvailable: Bool { true }
    public var isActive: Bool { coordinator?.isMirroring == true && coordinator?.selectedDevice?.transport == .wifi }
    public var status: SourceAdapterStatus {
        if isActive { return .streaming }
        return .idle
    }
    public var telemetryFps: Double { coordinator?.currentFps ?? 0.0 }
    public var telemetryLatencyMs: Double { coordinator?.currentLatencyMs ?? 0.0 }

    private weak var coordinator: MirroringCoordinator?

    public init(coordinator: MirroringCoordinator) {
        self.coordinator = coordinator
    }

    public func start() -> Bool {
        coordinator?.startMirroring()
        return true
    }

    public func stop() {
        coordinator?.stopMirroring()
    }
}

// =================================================================================================
// 4. IosLanSourceAdapter — Manages CastSprint iOS companion app over Wi-Fi
// =================================================================================================
public final class IosLanSourceAdapter: SourceAdapter {
    public let type: SourceAdapterType = .iosLan
    public let name: String = "iPhone Wi-Fi (CastSprint iOS App)"
    public var isAvailable: Bool { true }
    public var isActive: Bool { coordinator?.isMirroring == true && coordinator?.selectedDevice?.platform == .ios && coordinator?.selectedDevice?.transport == .wifi }
    public var status: SourceAdapterStatus {
        if isActive { return .streaming }
        return .idle
    }
    public var telemetryFps: Double { coordinator?.currentFps ?? 0.0 }
    public var telemetryLatencyMs: Double { coordinator?.currentLatencyMs ?? 0.0 }

    private weak var coordinator: MirroringCoordinator?

    public init(coordinator: MirroringCoordinator) {
        self.coordinator = coordinator
    }

    public func start() -> Bool {
        coordinator?.startMirroring()
        return true
    }

    public func stop() {
        coordinator?.stopMirroring()
    }
}

// =================================================================================================
// 5. AirPlayReceiverSourceAdapter — Zero-App AirPlay metadata adapter
// =================================================================================================
public final class AirPlayReceiverSourceAdapter: SourceAdapter {
    public let type: SourceAdapterType = .airPlayReceiver
    public let name: String = "iPhone AirPlay (Zero App Wi-Fi)"
    public var isAvailable: Bool { false } // Native AirPlay receiver engine is active on Windows; macOS uses Apple AirPlay Receiver or CoreMediaIO USB
    public var isActive: Bool { false }
    public var status: SourceAdapterStatus { .idle }
    public var telemetryFps: Double { 0.0 }
    public var telemetryLatencyMs: Double { 0.0 }

    public init() {}
    public func start() -> Bool { false }
    public func stop() {}
}

// =================================================================================================
// 6. ExperimentalIosUsbWindowsSourceAdapter — Windows NDIS Hotspot adapter (Blocked/N/A on Mac)
// =================================================================================================
public final class ExperimentalIosUsbWindowsSourceAdapter: SourceAdapter {
    public let type: SourceAdapterType = .experimentalIosUsbWindows
    public let name: String = "iPhone USB Hotspot (Windows NDIS)"
    public var isAvailable: Bool { false } // Not applicable on macOS (macOS provides direct CoreMediaIO without Hotspot)
    public var isActive: Bool { false }
    public var status: SourceAdapterStatus { .error("Not applicable on macOS. Mac uses native CoreMediaIO USB capture without requiring Personal Hotspot.") }
    public var telemetryFps: Double { 0.0 }
    public var telemetryLatencyMs: Double { 0.0 }

    public init() {}
    public func start() -> Bool { false }
    public func stop() {}
}
