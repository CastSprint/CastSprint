// LegacyBroadcastCaptureSource.swift — ReplayKit Broadcast Upload Extension Adapter
// Provides universal App Store compatible screen capture on iOS 14 through current versions.
import Foundation
import CoreMedia
import CoreVideo
import ReplayKit

public final class LegacyBroadcastCaptureSource: NSObject, ScreenCaptureSource {
    public weak var delegate: ScreenCaptureSourceDelegate?

    public private(set) var isCapturing: Bool = false
    public var isMicrophoneEnabled: Bool = false {
        didSet {
            var config = AppGroupBridge.shared.loadConfiguration()
            config.isMicrophoneEnabled = isMicrophoneEnabled
            AppGroupBridge.shared.saveConfiguration(config)
        }
    }
    public private(set) var currentOrientation: CaptureOrientation = .portrait

    private var pollTimer: Timer?
    private let appGroup = AppGroupBridge.shared

    public override init() {
        super.init()
    }

    deinit {
        stopMonitoring()
    }

    public func requestCaptureAuthorization(completion: @escaping (Result<Bool, CaptureError>) -> Void) {
        if RPScreenRecorder.shared().isAvailable {
            completion(.success(true))
        } else {
            completion(.failure(.permissionDenied))
        }
    }

    public func startCapture() throws {
        guard RPScreenRecorder.shared().isAvailable else {
            throw CaptureError.permissionDenied
        }

        // In ReplayKit Broadcast Upload Extension architecture, the system presents
        // RPSystemBroadcastPickerView to the user to authorize and launch the extension.
        // The containing app prepares the shared state and monitors extension lifecycle.
        startMonitoring()
    }

    public func pauseCapture() {
        isCapturing = false
        appGroup.updateBroadcastState("paused")
        delegate?.captureSourceDidPause(self)
    }

    public func resumeCapture() {
        isCapturing = true
        appGroup.updateBroadcastState("streaming")
        delegate?.captureSourceDidResume(self)
    }

    public func stopCapture() {
        isCapturing = false
        stopMonitoring()
        appGroup.updateBroadcastState("stopped")
        delegate?.captureSourceDidStop(self)
    }

    // MARK: - App Group State Monitoring

    private func startMonitoring() {
        stopMonitoring()
        // Poll App Group state every 500ms while active
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkExtensionState()
            }
        }
    }

    private func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkExtensionState() {
        let (state, error, timestamp) = appGroup.readBroadcastState()

        // Verify state is recent (within 5 seconds)
        let now = Date().timeIntervalSince1970
        guard (now - timestamp) < 5.0 else { return }

        switch state {
        case "streaming":
            if !isCapturing {
                isCapturing = true
                delegate?.captureSourceDidResume(self)
            }
        case "paused":
            if isCapturing {
                isCapturing = false
                delegate?.captureSourceDidPause(self)
            }
        case "stopped":
            if isCapturing {
                isCapturing = false
                delegate?.captureSourceDidStop(self)
            }
        case "error":
            isCapturing = false
            let errString = error ?? "Unknown broadcast error"
            delegate?.captureSource(self, didEncounterError: .internalError(errString))
            delegate?.captureSourceDidStop(self)
        default:
            break
        }
    }
}
