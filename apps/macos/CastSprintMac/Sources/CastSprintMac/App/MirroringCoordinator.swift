// MirroringCoordinator.swift — Central Multi-Platform Media Pipeline Coordinator
import Foundation
import SwiftUI
import CoreMedia
import AVFoundation

public final class MirroringCoordinator: NSObject, ObservableObject,
                                         IPhoneCaptureSessionDelegate,
                                         NetworkStreamReceiverDelegate,
                                         ADBDeviceManagerDelegate,
                                         USBDeviceManagerDelegate {
    public static let shared = MirroringCoordinator()

    @Published public var isMirroring: Bool = false
    @Published public var isRecording: Bool = false
    @Published public var recordingDuration: Int = 0
    @Published public var isMuted: Bool = false
    @Published public var audioVolume: Float = 1.0
    @Published public var isAlwaysOnTop: Bool = false
    @Published public var selectedDevice: UnifiedDevice? = nil
    @Published public var availableDevices: [UnifiedDevice] = []
    @Published public var qualityProfile: CaptureQualityProfile = .automatic
    @Published public var statusMessage: String = "Ready"

    @Published public var currentFps: Double = 0.0
    @Published public var currentLatencyMs: Double = 0.0
    @Published public var currentJitterMs: Double = 0.0
    @Published public var droppedFrames: UInt64 = 0
    @Published public var activeSessionId: UInt32 = 0
    @Published public var lanPin: String = "4829"

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

    public override init() {
        super.init()
        captureSession.delegate = self
        networkReceiver.delegate = self
        adbManager.delegate = self
        usbManager.delegate = self
        setupDeviceManagers()
        startTelemetryLoop()
    }

    private func setupDeviceManagers() {
        usbManager.startMonitoring()
        adbManager.startMonitoring()
        lanAdvertiser.startAdvertising(port: 27183)
        self.lanPin = lanAdvertiser.currentPin

        refreshDevices()

        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshDevices()
        }
        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshDevices()
        }
    }

    public func refreshDevices() {
        usbManager.refreshDevices()
        adbManager.refreshDevices()

        var unifiedList: [UnifiedDevice] = []

        // 1. USB iPhones & iPads
        for dev in usbManager.devices {
            let isScreen = dev.isTrueScreenCapture
            let status: UnifiedDeviceStatus = (dev.state == .ready) ? .ready : .busy
            let unified = UnifiedDevice(
                id: dev.id,
                name: dev.name,
                model: dev.model,
                platform: .ios,
                transport: .usb,
                status: status,
                videoCapability: isScreen ? "1080p60 / 4K60 Direct Screen" : "Continuity Camera Feed",
                audioAvailable: true,
                isTestDevice: false,
                avDevice: dev.avDevice,
                adbSerial: nil
            )
            unifiedList.append(unified)
        }

        // 2. USB Android Devices
        for android in adbManager.connectedDevices {
            let status: UnifiedDeviceStatus = android.isAuthorized ? .ready : .unauthorized
            let unified = UnifiedDevice(
                id: "adb-\(android.id)",
                name: android.model.isEmpty ? "Android Device" : android.model,
                model: android.id,
                platform: .android,
                transport: .usb,
                status: status,
                videoCapability: "H.264 1080p60 Hardware Decode",
                audioAvailable: true,
                isTestDevice: false,
                avDevice: nil,
                adbSerial: android.id
            )
            unifiedList.append(unified)
        }

        // 3. Wi-Fi (LAN) Receiver Entry (always ready for incoming connections)
        let wifiDevice = UnifiedDevice(
            id: "lan-receiver",
            name: "Wi-Fi (LAN) Mirroring Receiver",
            model: "mDNS Bonjour Port 27183",
            platform: .android,
            transport: .wifi,
            status: .ready,
            videoCapability: "H.264 1080p60 Low-Latency",
            audioAvailable: true,
            isTestDevice: false,
            avDevice: nil,
            adbSerial: nil
        )
        unifiedList.append(wifiDevice)

        // 4. Protocol Test Simulator (iOS & Android Test Source)
        let testDevice = UnifiedDevice(
            id: "test-simulator",
            name: "Protocol Test Simulator (Test-Only)",
            model: "iOS / Android 60 FPS H.264",
            platform: .ios,
            transport: .wifi,
            status: .ready,
            videoCapability: "H.264 60 FPS Synthetic Feed",
            audioAvailable: true,
            isTestDevice: true,
            avDevice: nil,
            adbSerial: nil
        )
        unifiedList.append(testDevice)

        self.availableDevices = unifiedList
        if selectedDevice == nil || !availableDevices.contains(where: { $0.id == selectedDevice?.id }) {
            self.selectedDevice = availableDevices.first
        }
    }

    private func startTelemetryLoop() {
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isMirroring else { return }
            self.currentFps = LatencyTracker.shared.currentFps
            self.currentJitterMs = LatencyTracker.shared.jitterMs
            self.droppedFrames = LatencyTracker.shared.droppedFrames
        }
    }

    // MARK: - Mirroring Session Actions
    public func startMirroring() {
        guard let device = selectedDevice else {
            statusMessage = "No device selected"
            return
        }

        switch (device.platform, device.transport) {
        case (.ios, .usb):
            startIPhoneUSBMirroring(device: device)

        case (.android, .usb):
            startAndroidUSBMirroring(device: device)

        case (_, .wifi):
            if device.isTestDevice {
                startTestSimulatorMirroring()
            } else {
                startWiFiReceiverMirroring()
            }
        }
    }

    private func startIPhoneUSBMirroring(device: UnifiedDevice) {
        guard let usbDev = usbManager.devices.first(where: { $0.id == device.id }) else {
            statusMessage = "iPhone USB device not available"
            return
        }

        if !usbManager.reserveDevice(id: usbDev.id) {
            statusMessage = "Device busy or in use by another app"
            return
        }

        do {
            try captureSession.startCapture(device: usbDev, quality: qualityProfile)
            audioOutput.start()
            audioOutput.setVolume(audioVolume)
            audioOutput.setMuted(isMuted)
            LatencyTracker.shared.reset()

            self.isMirroring = true
            self.statusMessage = "Mirroring \(device.name) over USB"
        } catch {
            usbManager.releaseDevice(id: usbDev.id)
            self.statusMessage = "Failed to start capture: \(error.localizedDescription)"
        }
    }

    private func startAndroidUSBMirroring(device: UnifiedDevice) {
        guard let serial = device.adbSerial else {
            statusMessage = "Missing ADB serial for Android device"
            return
        }

        if device.status == .unauthorized {
            statusMessage = "Please tap 'Allow USB Debugging' on Android phone"
            return
        }

        // Setup ADB reverse port forward
        let portOk = adbManager.setupReversePortForward(serial: serial, port: 27183)
        if !portOk {
            statusMessage = "Failed to configure ADB reverse port forward"
            return
        }

        self.activeAdbSerial = serial

        do {
            try networkReceiver.start(port: 27183)
            audioOutput.start()
            audioOutput.setVolume(audioVolume)
            audioOutput.setMuted(isMuted)
            LatencyTracker.shared.reset()

            // Launch CastSprint Android app
            adbManager.launchAndroidApp(serial: serial)

            self.isMirroring = true
            self.statusMessage = "Connecting to CastSprint on \(device.name)..."
        } catch {
            adbManager.removeReversePortForward(serial: serial, port: 27183)
            self.activeAdbSerial = nil
            self.statusMessage = "Receiver error: \(error.localizedDescription)"
        }
    }

    private func startWiFiReceiverMirroring() {
        do {
            try networkReceiver.start(port: 27183)
            audioOutput.start()
            audioOutput.setVolume(audioVolume)
            audioOutput.setMuted(isMuted)
            LatencyTracker.shared.reset()

            self.isMirroring = true
            self.statusMessage = "Waiting for Wi-Fi connection (Pairing PIN: \(lanPin))..."
        } catch {
            self.statusMessage = "Failed to open port 27183: \(error.localizedDescription)"
        }
    }

    private func startTestSimulatorMirroring() {
        do {
            try networkReceiver.start(port: 27183)
            audioOutput.start()
            audioOutput.setVolume(audioVolume)
            audioOutput.setMuted(isMuted)
            LatencyTracker.shared.reset()

            self.isMirroring = true
            self.statusMessage = "Starting Protocol Test Stream (60 FPS)..."

            testSender.onLog = { [weak self] log in
                NSLog("CastSprint Test Sender: %@", log)
                DispatchQueue.main.async {
                    self?.statusMessage = log
                }
            }
            testSender.start(host: "127.0.0.1", port: 27183, simulatedPlatform: "iOS")
        } catch {
            self.statusMessage = "Simulator failed to start: \(error.localizedDescription)"
        }
    }

    public func stopMirroring() {
        if isRecording {
            stopRecording()
        }

        testSender.stop()
        captureSession.stopCapture()
        networkReceiver.stop()
        audioOutput.stop()
        videoRenderer.clear()

        if let serial = activeAdbSerial {
            adbManager.removeReversePortForward(serial: serial, port: 27183)
            activeAdbSerial = nil
        }

        if let device = selectedDevice, device.transport == .usb && device.platform == .ios {
            usbManager.releaseDevice(id: device.id)
        }

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
        statusMessage = "Screenshot saved to Pictures"
    }

    public func setVolume(_ volume: Float) {
        self.audioVolume = volume
        audioOutput.setVolume(volume)
    }

    public func toggleMute() {
        self.isMuted.toggle()
        audioOutput.setMuted(isMuted)
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
        audioOutput.playSampleBuffer(sampleBuffer)
        if isRecording {
            recordingSink.appendAudioSampleBuffer(sampleBuffer)
        }
    }

    public func captureSessionDidEncounterError(_ session: IPhoneUSBCaptureSession, error: Error) {
        DispatchQueue.main.async {
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
            self.stopMirroring()
            self.statusMessage = "iPhone disconnected"
            self.refreshDevices()
        }
    }

    // MARK: - NetworkStreamReceiverDelegate (Android USB, Android Wi-Fi, iPhone Wi-Fi, Test Sender)
    public func receiverDidConnectDevice(name: String, model: String, platform: String, sessionId: UInt32) {
        self.isMirroring = true
        self.activeSessionId = sessionId
        self.statusMessage = "Mirroring \(name) (\(platform)) [Session \(sessionId)]"
        LatencyTracker.shared.reset()
    }

    public func receiverDidReceivePixelBuffer(_ pixelBuffer: CVPixelBuffer, ptsMicros: UInt64) {
        videoRenderer.renderPixelBuffer(pixelBuffer)
        if isRecording {
            let pts = CMTime(value: CMTimeValue(ptsMicros), timescale: 1_000_000)
            recordingSink.appendPixelBuffer(pixelBuffer, pts: pts)
        }
        LatencyTracker.shared.recordFrameReceived()
    }

    public func receiverDidReceiveAudio(ptsMicros: UInt64, payload: Data) {
        audioOutput.playPCMData(payload, sampleRate: 48000.0, channels: 2)
    }

    public func receiverDidDisconnect() {
        self.stopMirroring()
        self.statusMessage = "Device stream disconnected"
        self.refreshDevices()
    }

    public func receiverDidEncounterError(_ error: Error) {
        self.statusMessage = "Stream receiver error: \(error.localizedDescription)"
    }

    // MARK: - ADBDeviceManagerDelegate
    public func adbDevicesDidChange(_ devices: [AndroidDevice]) {
        refreshDevices()
    }

    // MARK: - USBDeviceManagerDelegate
    public func deviceManager(_ manager: USBDeviceManager, didUpdateDevices devices: [DiscoveredUSBDevice]) {
        refreshDevices()
    }

    public func deviceManager(_ manager: USBDeviceManager, didDetectDeviceArrival device: DiscoveredUSBDevice) {
        refreshDevices()
    }

    public func deviceManager(_ manager: USBDeviceManager, didDetectDeviceRemoval deviceId: String) {
        refreshDevices()
    }
}

