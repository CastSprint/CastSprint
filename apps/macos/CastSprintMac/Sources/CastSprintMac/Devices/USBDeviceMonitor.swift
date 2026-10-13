// USBDeviceMonitor.swift — USB Mobile Device Monitor (iOS and Android)
import Foundation
import AVFoundation

public struct ConnectedDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let model: String
    public let platform: String // "iOS" or "Android"
    public let avDevice: AVCaptureDevice?

    public init(id: String, name: String, model: String, platform: String, avDevice: AVCaptureDevice? = nil) {
        self.id = id
        self.name = name
        self.model = model
        self.platform = platform
        self.avDevice = avDevice
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: ConnectedDevice, rhs: ConnectedDevice) -> Bool {
        lhs.id == rhs.id
    }
}

public protocol USBDeviceMonitorDelegate: AnyObject {
    func devicesDidChange(_ devices: [ConnectedDevice])
}

public final class USBDeviceMonitor: NSObject {
    public weak var delegate: USBDeviceMonitorDelegate?
    private var isMonitoring = false
    private var cachedDevices: [ConnectedDevice] = []

    public override init() {
        super.init()
    }

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Ensure CoreMediaIO allows iOS devices
        CMIOManager.shared.enableScreenCaptureDevices()

        // Listen for AVFoundation device arrival/departure
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceConnectionChange),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceConnectionChange),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )

        refreshDevices()
    }

    public func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleDeviceConnectionChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshDevices()
        }
    }

    public func refreshDevices() {
        var devices: [ConnectedDevice] = []

        // 1. Discover iOS devices via AVFoundation
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )

        for dev in discovery.devices {
            let name = dev.localizedName
            let model = dev.modelID
            // Match iOS devices (iPhone or iPad)
            if name.contains("iPhone") || name.contains("iPad") || model.contains("iPhone") || model.contains("iPad") {
                let d = ConnectedDevice(
                    id: dev.uniqueID,
                    name: name,
                    model: model,
                    platform: "iOS",
                    avDevice: dev
                )
                devices.append(d)
            }
        }

        self.cachedDevices = devices
        delegate?.devicesDidChange(devices)
    }

    public var connectedDevices: [ConnectedDevice] {
        cachedDevices
    }
}
