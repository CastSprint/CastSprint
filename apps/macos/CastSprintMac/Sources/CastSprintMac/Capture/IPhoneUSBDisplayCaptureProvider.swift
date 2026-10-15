// IPhoneUSBDisplayCaptureProvider.swift — Dedicated Native iOS USB Screen Display Capture Provider
// CastSprint Multimedia Engineering
import Foundation
import AVFoundation
import CoreMediaIO

public enum IPhoneDisplayCaptureError: LocalizedError {
    case screenSourceNotFound
    case cameraPermissionDenied
    case deviceBusy(String)
    case sessionConfigurationFailed(String)
    case coreMediaIOFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .screenSourceNotFound:
            return "IPHONE_SCREEN_SOURCE_NOT_FOUND: No genuine iPhone display screen capture source detected over USB. Please unlock your iPhone 15, confirm 'Trust This Computer', and turn OFF Continuity Camera if active."
        case .cameraPermissionDenied:
            return "macOS capture permission is denied. Please enable permission in System Settings -> Privacy & Security."
        case .deviceBusy(let name):
            return "Device '\(name)' is in use by another application (e.g. QuickTime, OBS, or another capture utility)."
        case .sessionConfigurationFailed(let reason):
            return "Failed to configure capture session: \(reason)"
        case .coreMediaIOFailed(let status):
            return "CoreMediaIO system property initialization failed with OSStatus \(status)"
        }
    }
}

public protocol IPhoneUSBDisplayCaptureProviderDelegate: AnyObject {
    func displayCaptureProviderDidUpdateDevices(_ provider: IPhoneUSBDisplayCaptureProvider, devices: [DiscoveredUSBDevice])
}

public final class IPhoneUSBDisplayCaptureProvider: NSObject {
    public static let shared = IPhoneUSBDisplayCaptureProvider()

    public weak var delegate: IPhoneUSBDisplayCaptureProviderDelegate?

    private let cmioNotificationQueue = DispatchQueue(label: "com.castsprint.mac.cmio.device-events", qos: .userInitiated)
    private var cmioDevicesListener: CMIOObjectPropertyListenerBlock?
    private var isCMIOObserving = false
    private let discoveryQueue = DispatchQueue(label: "com.castsprint.mac.display.discovery", qos: .userInitiated)
    private var isRefreshing = false

    public private(set) var discoveredScreenDevices: [DiscoveredUSBDevice] = []

    public override init() {
        super.init()
        enableCoreMediaIOScreenCaptureDevices()
        observeCMIODeviceChanges()
        registerAVFoundationNotifications()
    }

    deinit {
        stopObservingCMIODeviceChanges()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - CoreMediaIO DAL Activation
    /// Apple's documented CoreMediaIO system API allowing iOS screen capture devices to be exposed to AVFoundation
    public func enableCoreMediaIOScreenCaptureDevices() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )
        if status == noErr {
            NSLog("CastSprint: CoreMediaIO screen capture device support enabled successfully (status=noErr)")
        } else {
            NSLog("CastSprint: Warning — CoreMediaIO CMIOObjectSetPropertyData returned OSStatus %d", status)
        }
    }

    // MARK: - Event-Driven Hardware Device Notification
    private func observeCMIODeviceChanges() {
        guard !isCMIOObserving else { return }
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.discoveryQueue.async {
                self?.refreshDevices()
            }
        }
        let status = CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            cmioNotificationQueue,
            listener
        )
        if status == noErr {
            self.cmioDevicesListener = listener
            self.isCMIOObserving = true
            NSLog("CastSprint: Registered CoreMediaIO hardware device listener successfully")
        }
    }

    private func stopObservingCMIODeviceChanges() {
        guard isCMIOObserving, let listener = cmioDevicesListener else { return }
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        CMIOObjectRemovePropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            cmioNotificationQueue,
            listener
        )
        self.cmioDevicesListener = nil
        self.isCMIOObserving = false
    }

    private func registerAVFoundationNotifications() {
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAVDeviceNotification(_:)),
                name: name,
                object: nil
            )
        }
    }

    @objc private func handleAVDeviceNotification(_ notification: Notification) {
        discoveryQueue.async { [weak self] in
            self?.refreshDevices()
        }
    }

    // MARK: - Device Discovery & Strict Screen Qualification
    public func refreshDevices() {
        guard !isRefreshing else { return }
        isRefreshing = true

        // 1. Discover using mediaType: .muxed (The authentic CoreMediaIO DAL iOS screen capture device)
        let muxedDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )

        var screenDevices: [DiscoveredUSBDevice] = []

        for dev in muxedDiscovery.devices {
            // Unconditionally reject any Continuity Camera or webcam
            if dev.isContinuityCamera { continue }
            if #available(macOS 14.0, *) {
                if dev.deviceType == .continuityCamera { continue }
            }
            if dev.deviceType == .builtInWideAngleCamera { continue }

            let nameLower = dev.localizedName.lowercased()
            let modelLower = dev.modelID.lowercased()
            if nameLower.contains("camera") || modelLower.contains("camera") ||
               nameLower.contains("desk view") || nameLower.contains("continuity") {
                continue // Rejects optical sensors
            }

            // Identify legitimate Apple display screen capture device
            let isApple = dev.manufacturer.lowercased().contains("apple") ||
                          dev.localizedName.contains("iPhone") || dev.localizedName.contains("iPad") ||
                          dev.modelID.contains("iPhone") || dev.modelID.contains("iPad")

            guard isApple else { continue }

            var state: DeviceState = .ready
            if dev.isSuspended {
                state = .suspended
            } else if dev.isInUseByAnotherApplication {
                state = .busyAnotherApp
            }

            let discovered = DiscoveredUSBDevice(
                id: dev.uniqueID,
                name: "\(dev.localizedName) (USB Screen)",
                model: dev.modelID.isEmpty ? "iPhone/iPad Screen (Muxed)" : dev.modelID,
                manufacturer: dev.manufacturer,
                isTrueScreenCapture: true,
                isContinuityCamera: false,
                state: state,
                avDevice: dev
            )
            screenDevices.append(discovered)
        }

        self.isRefreshing = false
        DispatchQueue.main.async {
            self.discoveredScreenDevices = screenDevices
            self.delegate?.displayCaptureProviderDidUpdateDevices(self, devices: screenDevices)
        }
    }

    /// Returns the primary legitimate iPhone USB screen capture device, or throws IPhoneDisplayCaptureError.screenSourceNotFound
    public func requireScreenDevice() throws -> DiscoveredUSBDevice {
        refreshDevices()
        guard let screen = discoveredScreenDevices.first(where: { $0.isTrueScreenCapture && $0.state != .busyAnotherApp }) else {
            throw IPhoneDisplayCaptureError.screenSourceNotFound
        }
        return screen
    }
}
