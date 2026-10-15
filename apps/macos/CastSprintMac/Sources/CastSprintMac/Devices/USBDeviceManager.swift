// USBDeviceManager.swift — Native iPhone/iPad USB Device Manager
import Foundation
import AVFoundation
import CoreMediaIO

public enum DeviceState: String {
    case ready = "Ready to Mirror"
    case inUse = "Mirroring Active"
    case busyAnotherApp = "In Use by Another App"
    case needsTrust = "Needs Trust / Passcode"
    case suspended = "Suspended"
    case disconnected = "Disconnected"
}

public struct DiscoveredUSBDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let model: String
    public let manufacturer: String
    public let isTrueScreenCapture: Bool
    public let isContinuityCamera: Bool
    public var state: DeviceState
    public let avDevice: AVCaptureDevice

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DiscoveredUSBDevice, rhs: DiscoveredUSBDevice) -> Bool {
        lhs.id == rhs.id && lhs.state == rhs.state && lhs.name == rhs.name && lhs.isTrueScreenCapture == rhs.isTrueScreenCapture
    }
}

public protocol USBDeviceManagerDelegate: AnyObject {
    func deviceManager(_ manager: USBDeviceManager, didUpdateDevices devices: [DiscoveredUSBDevice])
    func deviceManager(_ manager: USBDeviceManager, didDetectDeviceArrival device: DiscoveredUSBDevice)
    func deviceManager(_ manager: USBDeviceManager, didDetectDeviceRemoval deviceId: String)
}

public final class USBDeviceManager: NSObject {
    public static let shared = USBDeviceManager()

    public weak var delegate: USBDeviceManagerDelegate?

    private var activeReservations = Set<String>()
    private var knownDevices: [DiscoveredUSBDevice] = []
    private var isMonitoring = false
    private var isRefreshing = false
    private let refreshQueue = DispatchQueue(label: "com.castsprint.mac.devicemanager", qos: .userInitiated)

    public private(set) var cameraPermissionGranted: Bool = false
    public private(set) var microphonePermissionGranted: Bool = false

    public override init() {
        super.init()
        checkPermissions()
    }

    public func checkPermissions() {
        cameraPermissionGranted = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        microphonePermissionGranted = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    }

    public func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.cameraPermissionGranted = granted
                self?.refreshDevices()
                completion(granted)
            }
        }
    }

    public func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphonePermissionGranted = granted
                completion(granted)
            }
        }
    }

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Ensure CoreMediaIO allows screen capture devices
        CMIOManager.shared.enableScreenCaptureDevices()

        // Automatically prompt for video and audio access if not determined
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            requestCameraPermission { _ in }
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            requestMicrophonePermission { _ in }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceNotification),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceNotification),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )

        refreshDevices()
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleDeviceNotification(_ notification: Notification) {
        refreshDevices()
    }

    public func refreshDevices() {
        refreshQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isRefreshing else { return }
            self.isRefreshing = true

            // Ensure CoreMediaIO screen capture is active
            CMIOManager.shared.enableScreenCaptureDevices()

            // Enumerate video devices
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                mediaType: .video,
                position: .unspecified
            )

            var updatedList: [DiscoveredUSBDevice] = []

            for dev in discovery.devices {
                let isBuiltIn = (dev.deviceType == .builtInWideAngleCamera)
                if isBuiltIn {
                    continue // Do not present Mac's built-in webcam as a mobile capture device
                }

                // Apple names external USB connected iPhone/iPad camera: "[Device Name] Camera"
                // On macOS Ventura/Sonoma/Sequoia, an AVCaptureDevice from an iPhone represents its physical camera lens (Continuity Camera).
                let isCameraFeed = (dev.deviceType == .continuityCamera) ||
                                   dev.localizedName.contains("Continuity") ||
                                   dev.localizedName.contains("Camera") ||
                                   dev.modelID.contains("Camera")

                // A screen capture device must not be a physical camera lens
                let isScreen = !isBuiltIn && !isCameraFeed &&
                               (dev.localizedName.contains("Screen") || dev.modelID.contains("Screen"))

                let displayName = dev.localizedName

                var state: DeviceState = .ready
                if dev.isSuspended {
                    state = .suspended
                } else if dev.isInUseByAnotherApplication {
                    state = .busyAnotherApp
                } else if self.activeReservations.contains(dev.uniqueID) {
                    state = .inUse
                }

                let discovered = DiscoveredUSBDevice(
                    id: dev.uniqueID,
                    name: displayName,
                    model: dev.modelID,
                    manufacturer: dev.manufacturer,
                    isTrueScreenCapture: isScreen,
                    isContinuityCamera: isCameraFeed,
                    state: state,
                    avDevice: dev
                )

                updatedList.append(discovered)
            }

            DispatchQueue.main.async {
                self.isRefreshing = false
                if self.knownDevices != updatedList {
                    self.knownDevices = updatedList
                    self.delegate?.deviceManager(self, didUpdateDevices: updatedList)
                }
            }
        }
    }

    public var devices: [DiscoveredUSBDevice] {
        knownDevices
    }

    public var availableScreenSources: [DiscoveredUSBDevice] {
        knownDevices.filter { $0.isTrueScreenCapture && $0.state != .busyAnotherApp }
    }

    // MARK: - Device Reservation
    public func reserveDevice(id: String) -> Bool {
        if activeReservations.contains(id) {
            return false // Already reserved
        }
        activeReservations.insert(id)
        refreshDevices()
        return true
    }

    public func releaseDevice(id: String) {
        activeReservations.remove(id)
        refreshDevices()
    }
}
