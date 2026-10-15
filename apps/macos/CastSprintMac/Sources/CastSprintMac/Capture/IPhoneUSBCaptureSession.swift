// IPhoneUSBCaptureSession.swift — Native iPhone USB Capture Session
import Foundation
import AVFoundation
import CoreMedia

public enum CaptureQualityProfile: String, CaseIterable, Identifiable {
    case automatic = "Automatic (Best Available)"
    case performance = "Performance (720p 60fps)"
    case balanced = "Balanced (1080p 60fps)"
    case quality = "Quality (Native Resolution)"

    public var id: String { rawValue }
}

public protocol IPhoneCaptureSessionDelegate: AnyObject {
    func captureSession(_ session: IPhoneUSBCaptureSession, didOutputVideo sampleBuffer: CMSampleBuffer)
    func captureSession(_ session: IPhoneUSBCaptureSession, didOutputAudio sampleBuffer: CMSampleBuffer)
    func captureSessionDidEncounterError(_ session: IPhoneUSBCaptureSession, error: Error)
    func captureSessionWasInterrupted(_ session: IPhoneUSBCaptureSession)
    func captureSessionInterruptionEnded(_ session: IPhoneUSBCaptureSession)
    func captureSessionDeviceDidDisconnect(_ session: IPhoneUSBCaptureSession)
}

public final class IPhoneUSBCaptureSession: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate {

    public weak var delegate: IPhoneCaptureSessionDelegate?

    private var captureSession: AVCaptureSession?
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioPreviewOutput: AVCaptureAudioPreviewOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?

    private let videoQueue = DispatchQueue(label: "com.castsprint.mac.capture.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.castsprint.mac.capture.audio", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "com.castsprint.mac.capture.session")

    private(set) public var isRunning = false
    private(set) public var activeDevice: DiscoveredUSBDevice?
    private(set) public var isAudioPreviewActive: Bool = false
    private(set) public var audioSourceDescription: String = "No digital audio source"
    public var currentQuality: CaptureQualityProfile = .automatic

    public override init() {
        super.init()
    }

    public func startCapture(
        device: DiscoveredUSBDevice,
        quality: CaptureQualityProfile = .automatic,
        includeAudio: Bool = true
    ) throws {
        guard device.isTrueScreenCapture else {
            throw NSError(domain: "CastSprint", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Refusing to start capture on camera sensor '\(device.name)'. Only genuine screen display sources are permitted."
            ])
        }

        try sessionQueue.sync {
            stopCaptureInternal()

            self.currentQuality = quality
            let session = AVCaptureSession()
            session.beginConfiguration()

            // 1. Configure Muxed Video & Audio Input
            let avDevice = device.avDevice
            guard let vInput = try? AVCaptureDeviceInput(device: avDevice) else {
                session.commitConfiguration()
                throw NSError(domain: "CastSprint", code: -10, userInfo: [NSLocalizedDescriptionKey: "Failed to open video/muxed input for \(device.name)"])
            }

            if session.canAddInput(vInput) {
                session.addInput(vInput)
                self.videoInput = vInput
                let ports = vInput.ports.map { $0.mediaType.rawValue }
                self.audioSourceDescription = "\(avDevice.localizedName) · device type \(avDevice.deviceType.rawValue) · transport \(avDevice.transportType) · ports \(ports.joined(separator: ", "))"
            } else {
                session.commitConfiguration()
                throw NSError(domain: "CastSprint", code: -11, userInfo: [NSLocalizedDescriptionKey: "Cannot add muxed display input to AVCaptureSession"])
            }

            // 2. Select Optimal Video Preset & Device Format
            let targetPresets: [AVCaptureSession.Preset]
            switch quality {
            case .performance: targetPresets = [.hd1280x720, .low, .high]
            case .balanced: targetPresets = [.hd1920x1080, .medium, .high]
            case .quality, .automatic: targetPresets = [.high, .hd1920x1080]
            }
            for preset in targetPresets {
                if session.canSetSessionPreset(preset) {
                    session.sessionPreset = preset
                    break
                }
            }
            configureFormat(for: avDevice, quality: quality)

            // 3. Configure Video Output
            let vOutput = AVCaptureVideoDataOutput()
            // iPhone and iPad screen devices expose a muxed native format that does
            // not permit callers to force a pixel format. Let AVFoundation choose its
            // default uncompressed output so the capture graph performs conversion natively.
            vOutput.videoSettings = nil
            vOutput.alwaysDiscardsLateVideoFrames = false
            vOutput.setSampleBufferDelegate(self, queue: videoQueue)

            if session.canAddOutput(vOutput) {
                session.addOutput(vOutput)
                self.videoOutput = vOutput
            }

            // 4. Configure Muxed Internal Game Audio
            // A. Audio Preview Output: Routes the phone's sound directly to the Mac's speakers (QuickTime parity)
            if includeAudio {
                let previewOut = AVCaptureAudioPreviewOutput()
                previewOut.volume = 1.0
                if session.canAddOutput(previewOut) {
                    session.addOutput(previewOut)
                    self.audioPreviewOutput = previewOut
                    self.isAudioPreviewActive = true
                } else {
                    self.isAudioPreviewActive = false
                }

                // B. Audio Data Output: Delivers audio CMSampleBuffers for recording.
                let dataOut = AVCaptureAudioDataOutput()
                dataOut.setSampleBufferDelegate(self, queue: audioQueue)
                if session.canAddOutput(dataOut) {
                    session.addOutput(dataOut)
                    self.audioDataOutput = dataOut
                }
            } else {
                self.isAudioPreviewActive = false
                self.audioSourceDescription += " · audio permission unavailable (video only)"
            }

            session.commitConfiguration()
            session.startRunning()

            self.captureSession = session
            self.isRunning = true
            self.activeDevice = device

            PipelineTelemetry.shared.recordCaptureSessionStarted(true)
            registerSessionObservers()
            NSLog("CastSprint: Native USB screen & audio capture session started for %@ with profile %@", device.name, quality.rawValue)
        }
    }

    public func setAudioVolume(_ volume: Float) {
        audioPreviewOutput?.volume = volume
    }

    public func setAudioMuted(_ muted: Bool) {
        audioPreviewOutput?.volume = muted ? 0.0 : 1.0
    }

    public func stopCapture() {
        sessionQueue.sync {
            stopCaptureInternal()
        }
    }

    private func stopCaptureInternal() {
        guard isRunning, let session = captureSession else { return }
        unregisterSessionObservers()
        session.stopRunning()

        self.captureSession = nil
        self.videoInput = nil
        self.videoOutput = nil
        self.audioPreviewOutput = nil
        self.audioDataOutput = nil
        self.isRunning = false
        self.isAudioPreviewActive = false
        self.audioSourceDescription = "No digital audio source"
        self.activeDevice = nil
        PipelineTelemetry.shared.recordCaptureSessionStarted(false)
        NSLog("CastSprint: Capture session stopped")
    }

    private func configureFormat(for device: AVCaptureDevice, quality: CaptureQualityProfile) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let formats = device.formats
            var bestFormat: AVCaptureDevice.Format? = nil
            var maxFps: Double = 0
            var bestArea: Int32 = 0

            for format in formats {
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let frameRates = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }
                let formatMaxFps = frameRates.max() ?? 30.0
                let area = dims.width * dims.height

                switch quality {
                case .performance:
                    // Prefer 720p @ 60fps
                    if dims.height <= 720 && formatMaxFps >= 60.0 {
                        bestFormat = format
                    }
                case .balanced:
                    // Prefer 1080p @ 60fps
                    if dims.height <= 1080 && formatMaxFps >= 60.0 {
                        bestFormat = format
                    }
                case .quality, .automatic:
                    // Highest available resolution and framerate
                    if formatMaxFps > maxFps || (formatMaxFps == maxFps && area >= bestArea) {
                        maxFps = formatMaxFps
                        bestArea = area
                        bestFormat = format
                    }
                }
            }

            if let selected = bestFormat {
                device.activeFormat = selected
                // Lock to maximum frame rate (60 FPS)
                if let maxRange = selected.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                    device.activeVideoMinFrameDuration = maxRange.minFrameDuration
                    device.activeVideoMaxFrameDuration = maxRange.minFrameDuration
                }
            }
        } catch {
            NSLog("CastSprint: Warning — Failed to lock device for format configuration: %@", error.localizedDescription)
        }
    }

    // MARK: - Notification Observers
    private func registerSessionObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSessionRuntimeError),
            name: .AVCaptureSessionRuntimeError, object: captureSession
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSessionInterrupted),
            name: .AVCaptureSessionWasInterrupted, object: captureSession
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded, object: captureSession
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDeviceDisconnected),
            name: .AVCaptureDeviceWasDisconnected, object: activeDevice?.avDevice
        )
    }

    private func unregisterSessionObservers() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleSessionRuntimeError(notification: Notification) {
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error {
            NSLog("CastSprint: Capture session runtime error: %@", error.localizedDescription)
            delegate?.captureSessionDidEncounterError(self, error: error)
        }
    }

    @objc private func handleSessionInterrupted(notification: Notification) {
        NSLog("CastSprint: Capture session interrupted")
        delegate?.captureSessionWasInterrupted(self)
    }

    @objc private func handleSessionInterruptionEnded(notification: Notification) {
        NSLog("CastSprint: Capture session interruption ended")
        delegate?.captureSessionInterruptionEnded(self)
    }

    @objc private func handleDeviceDisconnected(notification: Notification) {
        NSLog("CastSprint: Active capture device disconnected")
        delegate?.captureSessionDeviceDidDisconnect(self)
        stopCapture()
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOutput {
            guard CMSampleBufferIsValid(sampleBuffer) else { return }
            PipelineTelemetry.shared.recordCaptureSample(buffer: sampleBuffer)
            delegate?.captureSession(self, didOutputVideo: sampleBuffer)
        } else if output === audioDataOutput {
            PipelineTelemetry.shared.recordAudioSample()
            delegate?.captureSession(self, didOutputAudio: sampleBuffer)
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Late frames discarded to prioritize real-time gameplay latency
    }
}
