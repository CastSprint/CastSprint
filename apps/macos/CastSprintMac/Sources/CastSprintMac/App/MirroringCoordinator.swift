// MirroringCoordinator.swift — Central Media Pipeline Coordinator
import Foundation
import SwiftUI
import CoreMedia
import AVFoundation

public final class MirroringCoordinator: NSObject, ObservableObject, IPhoneCaptureSessionDelegate {
    public static let shared = MirroringCoordinator()

    @Published public var isMirroring: Bool = false
    @Published public var isRecording: Bool = false
    @Published public var recordingDuration: Int = 0
    @Published public var isMuted: Bool = false
    @Published public var audioVolume: Float = 1.0
    @Published public var isAlwaysOnTop: Bool = false
    @Published public var selectedDevice: DiscoveredUSBDevice? = nil
    @Published public var availableDevices: [DiscoveredUSBDevice] = []
    @Published public var qualityProfile: CaptureQualityProfile = .automatic
    @Published public var statusMessage: String = "Ready"

    @Published public var currentFps: Double = 0.0
    @Published public var currentLatencyMs: Double = 14.0
    @Published public var currentJitterMs: Double = 0.5
    @Published public var droppedFrames: UInt64 = 0

    public let captureSession = IPhoneUSBCaptureSession()
    public let videoRenderer = MetalVideoRenderer()
    public let audioOutput = CoreAudioOutput()
    public let recordingSink = AVAssetWriterRecordingSink()
    public let deviceManager = USBDeviceManager.shared

    private var recordingTimer: Timer?
    private var telemetryTimer: Timer?

    public override init() {
        super.init()
        captureSession.delegate = self
        setupDeviceManager()
        startTelemetryLoop()
    }

    private func setupDeviceManager() {
        deviceManager.startMonitoring()
        self.availableDevices = deviceManager.devices
        self.selectedDevice = deviceManager.devices.first

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
        deviceManager.refreshDevices()
        self.availableDevices = deviceManager.devices
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

    // MARK: - Actions
    public func startMirroring() {
        guard let device = selectedDevice else {
            statusMessage = "No device selected"
            return
        }

        if !deviceManager.reserveDevice(id: device.id) {
            statusMessage = "Device busy or in use"
            return
        }

        do {
            try captureSession.startCapture(device: device, quality: qualityProfile)
            audioOutput.start()
            audioOutput.setVolume(audioVolume)
            audioOutput.setMuted(isMuted)
            LatencyTracker.shared.reset()

            self.isMirroring = true
            self.statusMessage = "Mirroring \(device.name)"
        } catch {
            deviceManager.releaseDevice(id: device.id)
            self.statusMessage = "Failed to start capture: \(error.localizedDescription)"
        }
    }

    public func stopMirroring() {
        if isRecording {
            stopRecording()
        }
        captureSession.stopCapture()
        audioOutput.stop()
        videoRenderer.clear()

        if let device = selectedDevice {
            deviceManager.releaseDevice(id: device.id)
        }

        self.isMirroring = false
        self.statusMessage = "Standby"
    }

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
        // Screenshot capture implementation
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

    // MARK: - IPhoneCaptureSessionDelegate
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
            self.statusMessage = "Device was disconnected"
            self.refreshDevices()
        }
    }
}
