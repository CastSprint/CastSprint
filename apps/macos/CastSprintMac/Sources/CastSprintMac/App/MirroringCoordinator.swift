// MirroringCoordinator.swift — Central Multi-Platform Media Pipeline Coordinator
import Foundation
import SwiftUI
import CoreMedia
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum SessionState: String {
    case idle = "IDLE"
    case listening = "LISTENING"
    case pairing = "PAIRING"
    case authenticated = "AUTHENTICATED"
    case negotiating = "NEGOTIATING"
    case waitingForVideo = "WAITING_FOR_VIDEO"
    case receivingVideo = "RECEIVING_VIDEO"
    case rendering = "RENDERING"
    case disconnected = "DISCONNECTED"
    case error = "ERROR"
}

public enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case mirror = "Mirror View"
    case settings = "Settings"

    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .home: return "house.fill"
        case .mirror: return "display"
        case .settings: return "gearshape.fill"
        }
    }
}

public final class MirroringCoordinator: NSObject, ObservableObject,
                                         IPhoneCaptureSessionDelegate,
                                         NetworkStreamReceiverDelegate,
                                         ADBDeviceManagerDelegate,
                                         USBDeviceManagerDelegate,
                                         AndroidScreenrecordSessionDelegate {
    public static let shared = MirroringCoordinator()

    @Published public var sessionState: SessionState = .idle
    @Published public var activeTab: AppTab = .home
    @Published public var showHud: Bool = true
    @Published public var isMirroring: Bool = false
    @Published public var isRecording: Bool = false
    @Published public var recordingDuration: Int = 0
    @Published public var isMuted: Bool = false
    @Published public var audioVolume: Float = 1.0
    @Published public var capturePhoneAudio: Bool = false
    @Published public var isAlwaysOnTop: Bool = false
    @Published public var selectedDevice: UnifiedDevice? = nil
    @Published public var availableDevices: [UnifiedDevice] = []
    @Published public var qualityProfile: CaptureQualityProfile = .automatic
    @Published public var statusMessage: String = "Standby"

    @Published public var wirelessAdbHost: String = ""
    @Published public var wirelessAdbPort: String = "5555"
    @Published public var wirelessAdbCode: String = ""
    @Published public var wirelessAdbStatus: String = ""
    @Published public var isWirelessAdbBusy: Bool = false
    @Published public var isBleScanning: Bool = false

    @Published public var currentFps: Double = 0.0
    @Published public var captureFps: Double = 0.0
    @Published public var renderFps: Double = 0.0
    @Published public var gameplayWindowFps: Double = 0.0
    @Published public var capturePixelFormat: String = "None"
    @Published public var captureResolution: String = ""
    @Published public var currentLatencyMs: Double = 0.0
    @Published public var currentJitterMs: Double = 0.0
    @Published public var droppedFrames: UInt64 = 0
    @Published public var activeSessionId: UInt32 = 0
    @Published public var lanPin: String = "4829"
    @Published public var hasDeliveredFirstFrame: Bool = false

    public var isContinuityCameraActive: Bool {
        usbManager.devices.contains(where: { $0.isContinuityCamera })
    }

    public let captureSession = IPhoneUSBCaptureSession()
    public let videoRenderer = MetalVideoRenderer()
    public let audioOutput = CoreAudioOutput()
    public let recordingSink = AVAssetWriterRecordingSink()
    public let usbManager = USBDeviceManager.shared
    public let adbManager = ADBDeviceManager.shared
    public let lanAdvertiser = LanDiscoveryAdvertiser.shared
    public let networkReceiver = NetworkStreamReceiver()
    public let testSender = CastSprintTestSender()

    private var recordingTimer: Timer?
    private var telemetryTimer: Timer?
    private var activeAdbSerial: String?
    private var androidScreenrecordSession: AndroidScreenrecordSession?

    public override init() {
        super.init()
        captureSession.delegate = self
        networkReceiver.delegate = self
        adbManager.delegate = self
        usbManager.delegate = self

        videoRenderer.onFramePresented = { [weak self] in
            guard let self = self else { return }
            if !self.hasDeliveredFirstFrame {
                self.hasDeliveredFirstFrame = true
                self.sessionState = .rendering
                self.statusMessage = "Live Display Mirroring: \(self.selectedDevice?.name ?? "iPhone Screen")"
            }
        }

        setupDeviceManagers()
    }

    private func setupDeviceManagers() {
        usbManager.startMonitoring()
        adbManager.startMonitoring()
        lanAdvertiser.startAdvertising(port: 27183)
        self.lanPin = lanAdvertiser.currentPin

        refreshDevices()
    }

    public func refreshDevices() {
        usbManager.refreshDevices()
        adbManager.refreshDevices()
        rebuildUnifiedDeviceList()
    }

    public func rebuildUnifiedDeviceList() {
        var unifiedList: [UnifiedDevice] = []

        // 1. USB iPhones & iPads (Real Display Screen Only - Strictly Exclude Camera/Continuity Camera)
        for dev in usbManager.devices {
            guard dev.isTrueScreenCapture else {
                // Do NOT wrap an optical camera sensor as a screen capture device!
                continue
            }

            let cleanName = dev.name.replacingOccurrences(of: " Camera", with: "")
                                    .replacingOccurrences(of: " Microphone", with: "")
                                    .replacingOccurrences(of: " (Camera Feed)", with: "")
                                    .replacingOccurrences(of: " Desk View", with: "")
                                    .trimmingCharacters(in: .whitespaces)

            let screenDevice = UnifiedDevice(
                id: "screen-\(dev.id)",
                name: "\(cleanName) (USB Screen)",
                model: "Wired Display · OBS Ready",
                platform: .ios,
                transport: .usb,
                status: (dev.state == .ready || dev.state == .inUse) ? .ready : .busy,
                videoCapability: "1080p60 Metal GPU Display",
                audioAvailable: true, // Muxed USB audio delivers game sound directly to Mac speakers & recording
                isTestDevice: false,
                avDevice: dev.avDevice,
                adbSerial: nil
            )
            unifiedList.append(screenDevice)
        }


        // 2. USB Android Devices. Expose app-based gaming and app-less quick mirror separately.
        for android in adbManager.connectedDevices {
            let status: UnifiedDeviceStatus = android.isAuthorized ? .ready : .unauthorized
            let isWireless = android.id.contains(":")
            let transport: DeviceTransportType = isWireless ? .wifi : .usb
            let baseName = android.model.isEmpty ? "Android Device" : android.model
            let unified = UnifiedDevice(
                id: isWireless ? "adb-quick-\(android.id)" : "adb-app-\(android.id)",
                name: isWireless ? baseName : "\(baseName) — USB Gaming",
                model: android.id,
                platform: .android,
                transport: transport,
                status: status,
                videoCapability: isWireless ? "H.264 1080p60 Wireless ADB" : "APK H.264 + Internal Audio over ADB Reverse",
                audioAvailable: true,
                isTestDevice: false,
                avDevice: nil,
                adbSerial: android.id
            )
            unifiedList.append(unified)
            if !isWireless {
                unifiedList.append(UnifiedDevice(
                    id: "adb-quick-\(android.id)",
                    name: "\(baseName) — USB Quick Mirror",
                    model: android.id,
                    platform: .android,
                    transport: .usb,
                    status: status,
                    videoCapability: "App-Less H.264 Video · No Game Audio",
                    audioAvailable: false,
                    isTestDevice: false,
                    avDevice: nil,
                    adbSerial: android.id
                ))
            }
        }

        // 3. Wi-Fi (LAN) Receiver Entry (always ready for incoming connections)
        let wifiDevice = UnifiedDevice(
            id: "lan-receiver",
            name: "Wi-Fi (LAN) Mirroring Receiver",
            model: "mDNS Bonjour Port 27183",
            platform: .universal,
            transport: .wifi,
            status: .ready,
            videoCapability: "H.264 1080p60 Low-Latency",
            audioAvailable: true,
            isTestDevice: false,
            avDevice: nil,
            adbSerial: nil
        )
        unifiedList.append(wifiDevice)

#if DEBUG
        // 4. Protocol Test Simulator (Debug-Only Test Source)
        let testDevice = UnifiedDevice(
            id: "test-simulator",
            name: "Protocol Test Simulator (Debug-Only)",
            model: "iOS / Android 60 FPS H.264",
            platform: .universal,
            transport: .wifi,
            status: .ready,
            videoCapability: "H.264 60 FPS Synthetic Feed",
            audioAvailable: true,
            isTestDevice: true,
            avDevice: nil,
            adbSerial: nil
        )
        unifiedList.append(testDevice)
#endif

        if self.availableDevices != unifiedList {
            self.availableDevices = unifiedList
        }
        if let screenReady = availableDevices.first(where: { $0.id.hasPrefix("screen-") && $0.status == .ready }),
           (selectedDevice == nil || selectedDevice?.id == "lan-receiver" || selectedDevice?.isTestDevice == true) {
            self.selectedDevice = screenReady
        } else if let physicalReady = availableDevices.first(where: { !$0.isTestDevice && $0.id != "lan-receiver" && $0.status == .ready }),
           (selectedDevice == nil || selectedDevice?.id == "lan-receiver" || selectedDevice?.isTestDevice == true) {
            self.selectedDevice = physicalReady
        } else if selectedDevice == nil || !availableDevices.contains(where: { $0.id == selectedDevice?.id }) {
            self.selectedDevice = availableDevices.first
        }
    }

    private func startTelemetryLoop() {
        stopTelemetryLoop()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isMirroring else { return }
            self.captureFps = PipelineTelemetry.shared.captureFps
            self.renderFps = PipelineTelemetry.shared.renderedFps
            self.gameplayWindowFps = PipelineTelemetry.shared.gameplayWindowFps
            self.currentFps = PipelineTelemetry.shared.renderedFps > 0 ? PipelineTelemetry.shared.renderedFps : PipelineTelemetry.shared.captureFps
            self.capturePixelFormat = PipelineTelemetry.shared.capturePixelFormat
            if PipelineTelemetry.shared.capturePixelWidth > 0 {
                self.captureResolution = "\(PipelineTelemetry.shared.capturePixelWidth)x\(PipelineTelemetry.shared.capturePixelHeight)"
            }
            self.currentJitterMs = LatencyTracker.shared.jitterMs
            self.droppedFrames = LatencyTracker.shared.droppedFrames
        }
    }

    private func stopTelemetryLoop() {
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        self.currentFps = 0.0
        self.captureFps = 0.0
        self.renderFps = 0.0
        self.gameplayWindowFps = 0.0
        self.capturePixelFormat = "None"
        self.captureResolution = ""
        self.currentLatencyMs = 0.0
        self.currentJitterMs = 0.0
        PipelineTelemetry.shared.reset()
    }

    // MARK: - Mirroring Session Actions
    public func startMirroring() {
        guard let device = selectedDevice else {
            statusMessage = "No device selected"
            return
        }

        switch (device.platform, device.transport) {
        case (.ios, .usb):
            startIPhoneScreenMirroring(device: device)

        case (.android, .usb):
            if device.id.hasPrefix("adb-app-") {
                startAndroidUSBGaming(device: device)
            } else {
                startAndroidUSBMirroring(device: device)
            }

        case (_, .wifi):
            if device.isTestDevice {
                startTestSimulatorMirroring()
            } else if device.platform == .android && device.adbSerial != nil {
                startAndroidUSBMirroring(device: device) // Wireless ADB routes through ADB reverse
            } else {
                startWiFiReceiverMirroring()
            }

        default:
            startWiFiReceiverMirroring()
        }
    }

    private func startIPhoneScreenMirroring(device: UnifiedDevice) {
        let rawId = device.id.replacingOccurrences(of: "screen-", with: "")
        guard let usbDev = usbManager.devices.first(where: { $0.id == rawId }) else {
            self.sessionState = .error
            statusMessage = "iPhone device not connected via USB"
            return
        }

        guard usbDev.isTrueScreenCapture else {
            self.sessionState = .error
            statusMessage = "Refusing to start capture: '\(usbDev.name)' is a camera sensor, not a screen. Turn OFF Continuity Camera on your iPhone."
            return
        }

        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startIPhoneScreenMirroring(device: device)
                    } else {
                        self?.sessionState = .error
                        self?.statusMessage = "Capture permission denied in macOS System Settings"
                    }
                }
            }
            return
        }
        let audioAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)
        if IPhoneUSBPrivacyPolicy.shouldRequestAudioAuthorization(
            audioEnabled: capturePhoneAudio,
            status: audioAuthorization
        ) {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.startIPhoneScreenMirroring(device: device)
                }
            }
            return
        }

        if !usbManager.reserveDevice(id: usbDev.id) {
            self.sessionState = .error
            statusMessage = "Device busy or in use by another app"
            return
        }

        do {
            self.hasDeliveredFirstFrame = false
            self.sessionState = .waitingForVideo
            self.statusMessage = "Connecting to iPhone display over USB..."

            try captureSession.startCapture(
                device: usbDev,
                quality: qualityProfile,
                includeAudio: IPhoneUSBPrivacyPolicy.shouldIncludeAudio(
                    audioEnabled: capturePhoneAudio,
                    status: AVCaptureDevice.authorizationStatus(for: .audio)
                )
            )
            if captureSession.isAudioPreviewActive {
                captureSession.setAudioVolume(audioVolume)
                captureSession.setAudioMuted(isMuted)
            } else {
                audioOutput.start()
                audioOutput.setVolume(audioVolume)
                audioOutput.setMuted(isMuted)
            }
            LatencyTracker.shared.reset()

            self.isMirroring = true
            startTelemetryLoop()
        } catch {
            usbManager.releaseDevice(id: usbDev.id)
            self.sessionState = .error
            self.statusMessage = "Failed to start capture: \(error.localizedDescription)"
        }
    }

    public func openAudioMIDISetup() {
        let path = "/System/Applications/Utilities/Audio MIDI Setup.app"
        let fallbackPath = "/Applications/Utilities/Audio MIDI Setup.app"
        let url = FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : URL(fileURLWithPath: fallbackPath)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] app, err in
            DispatchQueue.main.async {
                if app != nil {
                    self?.statusMessage = "Audio MIDI Setup opened. Click 'Enable' next to your iPhone to stream pure internal game audio over USB."
                } else {
                    self?.statusMessage = "Cannot open Audio MIDI Setup: \(err?.localizedDescription ?? "Not found")"
                }
            }
        }
    }

    private func startAndroidUSBMirroring(device: UnifiedDevice) {
        guard let serial = device.adbSerial else {
            self.sessionState = .error
            statusMessage = "Missing ADB serial for Android device"
            return
        }

        if device.status == .unauthorized {
            self.sessionState = .error
            statusMessage = "Please tap 'Allow USB Debugging' on Android phone"
            return
        }

        guard let adb = adbManager.adbPath else {
            self.sessionState = .error
            statusMessage = "ADB not found. Install platform-tools or stream over Wi-Fi."
            return
        }

        self.activeAdbSerial = serial

        do {
            self.hasDeliveredFirstFrame = false
            self.sessionState = .waitingForVideo
            self.statusMessage = "Starting native app-less Android USB screen mirroring on \(serial)..."

            let session = AndroidScreenrecordSession(serial: serial, adbPath: adb)
            session.delegate = self
            try session.start()
            self.androidScreenrecordSession = session

            self.isMirroring = true
            startTelemetryLoop()
        } catch {
            self.activeAdbSerial = nil
            self.sessionState = .error
            self.statusMessage = "Screenrecord error: \(error.localizedDescription)"
        }
    }

    private func startAndroidUSBGaming(device: UnifiedDevice) {
        guard let serial = device.adbSerial else {
            sessionState = .error
            statusMessage = "Missing ADB serial for Android device"
            return
        }
        guard device.status == .ready else {
            sessionState = .error
            statusMessage = "Authorize USB debugging on the selected Android phone"
            return
        }
        guard adbManager.setupReversePortForward(serial: serial, port: 27183) else {
            sessionState = .error
            statusMessage = "ADB reverse tunnel verification failed for \(serial)"
            return
        }

        do {
            hasDeliveredFirstFrame = false
            activeAdbSerial = serial
            sessionState = .listening
            statusMessage = "USB Gaming ready. Approve screen capture on the Android phone."
            try networkReceiver.start(port: 27183, pairingToken: lanPin)
            audioOutput.start()
            audioOutput.setVolume(audioVolume)
            audioOutput.setMuted(isMuted)
            LatencyTracker.shared.reset()
            isMirroring = true
            startTelemetryLoop()
            adbManager.launchAndroidApp(serial: serial, pairingToken: lanPin, port: 27183)
        } catch {
            adbManager.removeReversePortForward(serial: serial, port: 27183)
            activeAdbSerial = nil
            sessionState = .error
            statusMessage = "USB Gaming receiver failed: \(error.localizedDescription)"
        }
    }

    private func startWiFiReceiverMirroring() {
        do {
            self.hasDeliveredFirstFrame = false
            self.sessionState = .listening
            self.statusMessage = "Waiting for mobile phone to connect... (Pairing PIN: \(lanPin))"

            try networkReceiver.start(port: 27183, pairingToken: lanPin)
            audioOutput.start()
            audioOutput.setVolume(audioVolume)
            audioOutput.setMuted(isMuted)
            LatencyTracker.shared.reset()

            self.isMirroring = true
            startTelemetryLoop()
        } catch {
            self.sessionState = .error
            self.statusMessage = "Failed to open port 27183: \(error.localizedDescription)"
        }
    }

    private func startTestSimulatorMirroring() {
        do {
            self.hasDeliveredFirstFrame = false
            self.sessionState = .listening
            self.statusMessage = "Starting Protocol Test Stream (60 FPS)..."

            try networkReceiver.start(port: 27183, pairingToken: lanPin)
            audioOutput.start()
            audioOutput.setVolume(audioVolume)
            audioOutput.setMuted(isMuted)
            LatencyTracker.shared.reset()

            self.isMirroring = true
            startTelemetryLoop()

            testSender.onLog = { [weak self] log in
                NSLog("CastSprint Test Sender: %@", log)
                DispatchQueue.main.async {
                    self?.statusMessage = log
                }
            }
            testSender.start(host: "127.0.0.1", port: 27183, simulatedPlatform: "iOS", pairingToken: lanPin)
        } catch {
            self.sessionState = .error
            self.statusMessage = "Simulator failed to start: \(error.localizedDescription)"
        }
    }

    public func stopMirroring() {
        stopTelemetryLoop()
        if isRecording {
            stopRecording()
        }

        testSender.stop()
        captureSession.stopCapture()
        androidScreenrecordSession?.stop()
        androidScreenrecordSession = nil
        networkReceiver.stop()
        audioOutput.stop()
        videoRenderer.clear()

        if let serial = activeAdbSerial {
            adbManager.removeReversePortForward(serial: serial, port: 27183)
            activeAdbSerial = nil
        }

        if let device = selectedDevice, device.transport == .usb && device.platform == .ios {
            let rawId = device.id.replacingOccurrences(of: "screen-", with: "")
            usbManager.releaseDevice(id: rawId)
        }

        self.sessionState = .idle
        self.hasDeliveredFirstFrame = false
        self.isMirroring = false
        self.activeSessionId = 0
        self.statusMessage = "Standby"
    }

    // MARK: - Recording & Screenshots
    public func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    public func startRecording() {
        guard isMirroring else { return }

        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let castsprintDir = moviesDir.appendingPathComponent("CastSprint", isDirectory: true)
        try? FileManager.default.createDirectory(at: castsprintDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "CastSprint_\(formatter.string(from: Date())).mp4"
        let fileURL = castsprintDir.appendingPathComponent(filename)

        do {
            try recordingSink.startRecording(to: fileURL, videoWidth: videoRenderer.videoWidth, videoHeight: videoRenderer.videoHeight)
            self.isRecording = true
            self.recordingDuration = 0
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.recordingDuration += 1
            }
            statusMessage = "Recording to \(filename)"
        } catch {
            statusMessage = "Recording error: \(error.localizedDescription)"
        }
    }

    public func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingSink.stopRecording { [weak self] savedURL in
            self?.isRecording = false
            self?.recordingDuration = 0
            if let url = savedURL {
                self?.statusMessage = "Saved recording to \(url.lastPathComponent)"
            }
        }
    }

    public func takeScreenshot() {
        guard let cgImage = videoRenderer.captureSnapshot() else {
            statusMessage = "No video frame available to capture"
            return
        }
        let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        let castsprintDir = picturesDir.appendingPathComponent("CastSprint", isDirectory: true)
        try? FileManager.default.createDirectory(at: castsprintDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "CastSprint_Shot_\(formatter.string(from: Date())).png"
        let fileURL = castsprintDir.appendingPathComponent(filename)

        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            statusMessage = "Failed to create screenshot file"
            return
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        if CGImageDestinationFinalize(destination) {
            statusMessage = "Screenshot saved: \(filename)"
        } else {
            statusMessage = "Failed to save PNG screenshot"
        }
    }

    public func captureOneDiagnosticSourceFrame() {
        guard isMirroring else {
            statusMessage = "Start mirroring before capturing a diagnostic frame"
            return
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CastSprint/Diagnostics", isDirectory: true)
        statusMessage = "Diagnostic armed — waiting for one real source frame"
        videoRenderer.requestDiagnosticCapture(in: directory) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    self?.statusMessage = "Diagnostic frame saved: \(url.path)"
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                case .failure(let error):
                    self?.statusMessage = "Diagnostic capture failed: \(error.localizedDescription)"
                }
            }
        }
    }

    public func setVolume(_ volume: Float) {
        self.audioVolume = volume
        audioOutput.setVolume(volume)
        captureSession.setAudioVolume(volume)
    }

    public func toggleMute() {
        self.isMuted.toggle()
        audioOutput.setMuted(isMuted)
        captureSession.setAudioMuted(isMuted)
    }

    // MARK: - IPhoneCaptureSessionDelegate (iPhone USB)
    public func captureSession(_ session: IPhoneUSBCaptureSession, didOutputVideo sampleBuffer: CMSampleBuffer) {
        videoRenderer.renderSampleBuffer(sampleBuffer)
        if isRecording {
            recordingSink.appendVideoSampleBuffer(sampleBuffer)
        }
        LatencyTracker.shared.recordFrameReceived()
    }

    public func captureSession(_ session: IPhoneUSBCaptureSession, didOutputAudio sampleBuffer: CMSampleBuffer) {
        if !session.isAudioPreviewActive {
            audioOutput.playSampleBuffer(sampleBuffer)
        }
        if isRecording {
            recordingSink.appendAudioSampleBuffer(sampleBuffer)
        }
    }

    public func captureSessionDidEncounterError(_ session: IPhoneUSBCaptureSession, error: Error) {
        DispatchQueue.main.async {
            self.sessionState = .error
            self.statusMessage = "Capture error: \(error.localizedDescription)"
        }
    }

    public func captureSessionWasInterrupted(_ session: IPhoneUSBCaptureSession) {
        DispatchQueue.main.async {
            self.statusMessage = "Capture interrupted by system"
        }
    }

    public func captureSessionInterruptionEnded(_ session: IPhoneUSBCaptureSession) {
        DispatchQueue.main.async {
            self.statusMessage = "Capture resumed"
        }
    }

    public func captureSessionDeviceDidDisconnect(_ session: IPhoneUSBCaptureSession) {
        DispatchQueue.main.async {
            self.sessionState = .disconnected
            self.stopMirroring()
            self.statusMessage = "iPhone disconnected"
            self.rebuildUnifiedDeviceList()
        }
    }

    // MARK: - NetworkStreamReceiverDelegate
    public func receiverDidStartListening(port: UInt16) {
        self.sessionState = .listening
        self.statusMessage = "Waiting for mobile phone to connect... (Port \(port), PIN: \(lanPin))"
    }

    public func receiverDidAcceptConnection() {
        self.sessionState = .pairing
        self.statusMessage = "Phone connected. Verifying handshake..."
    }

    public func receiverDidConnectDevice(name: String, model: String, platform: String, sessionId: UInt32) {
        self.isMirroring = true
        self.activeSessionId = sessionId
        self.sessionState = .authenticated
        self.statusMessage = "Authenticated with \(name) (\(platform)) [Session \(sessionId)]. Waiting for video..."
        LatencyTracker.shared.reset()
    }

    public func receiverDidReceiveVideoConfig(width: UInt16, height: UInt16, fps: UInt16) {
        self.sessionState = .waitingForVideo
        self.statusMessage = "Decoder ready (\(width)x\(height) @ \(fps)fps). Awaiting first video frame..."
    }

    public func receiverDidReceivePixelBuffer(_ pixelBuffer: CVPixelBuffer, ptsMicros: UInt64) {
        videoRenderer.renderPixelBuffer(pixelBuffer)
        if isRecording {
            let pts = CMTime(value: CMTimeValue(ptsMicros), timescale: 1_000_000)
            recordingSink.appendPixelBuffer(pixelBuffer, pts: pts)
        }
        LatencyTracker.shared.recordFrameReceived()
        if !hasDeliveredFirstFrame {
            DispatchQueue.main.async {
                self.hasDeliveredFirstFrame = true
                self.sessionState = .rendering
                self.statusMessage = "Live Gameplay Mirroring: \(self.selectedDevice?.name ?? "Mobile Screen") [Session \(self.activeSessionId)]"
            }
        }
    }

    public func receiverDidReceiveAudio(ptsMicros: UInt64, payload: Data) {
        audioOutput.playNetworkAudioFrame(payload, ptsMicros: ptsMicros)
    }

    public func receiverDidReceiveAudioConfig(codec: UInt8, channels: UInt8, sampleRate: UInt32, codecConfig: Data) {
        audioOutput.configureNetworkAudio(
            codec: codec,
            sampleRate: Double(sampleRate),
            channels: UInt32(channels),
            codecConfig: codecConfig
        )
    }

    public func receiverDidDisconnect() {
        self.sessionState = .disconnected
        self.stopMirroring()
        self.statusMessage = "Device stream disconnected"
        self.rebuildUnifiedDeviceList()
    }

    public func receiverDidEncounterError(_ error: Error) {
        self.sessionState = .error
        self.statusMessage = "Stream receiver error: \(error.localizedDescription)"
    }


    // MARK: - ADBDeviceManagerDelegate
    public func adbDevicesDidChange(_ devices: [AndroidDevice]) {
        rebuildUnifiedDeviceList()
    }

    // MARK: - USBDeviceManagerDelegate
    public func deviceManager(_ manager: USBDeviceManager, didUpdateDevices devices: [DiscoveredUSBDevice]) {
        rebuildUnifiedDeviceList()
    }

    public func deviceManager(_ manager: USBDeviceManager, didDetectDeviceArrival device: DiscoveredUSBDevice) {
        rebuildUnifiedDeviceList()
    }

    public func deviceManager(_ manager: USBDeviceManager, didDetectDeviceRemoval deviceId: String) {
        rebuildUnifiedDeviceList()
    }

    // MARK: - AndroidScreenrecordSessionDelegate (App-Less USB Mirroring)
    public func androidSession(_ session: AndroidScreenrecordSession, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, pts: UInt64) {
        videoRenderer.renderPixelBuffer(pixelBuffer)
        if isRecording {
            let cmPts = CMTime(value: CMTimeValue(pts), timescale: 1_000_000)
            recordingSink.appendPixelBuffer(pixelBuffer, pts: cmPts)
        }
        LatencyTracker.shared.recordFrameReceived()
        if !hasDeliveredFirstFrame {
            DispatchQueue.main.async {
                self.hasDeliveredFirstFrame = true
                self.sessionState = .rendering
                self.statusMessage = "Live Display Mirroring: \(self.selectedDevice?.name ?? "Android Screen") [App-Less USB 60 FPS]"
            }
        }
    }

    public func androidSessionDidEncounterError(_ session: AndroidScreenrecordSession, error: Error) {
        DispatchQueue.main.async {
            self.sessionState = .error
            self.statusMessage = "Android USB error: \(error.localizedDescription)"
        }
    }

    public func androidSessionDidTerminate(_ session: AndroidScreenrecordSession) {
        DispatchQueue.main.async {
            self.sessionState = .disconnected
            self.statusMessage = "Android USB screenrecord ended"
        }
    }
}

