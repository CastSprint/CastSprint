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
    private var audioInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?

    private let videoQueue = DispatchQueue(label: "com.castsprint.mac.capture.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.castsprint.mac.capture.audio", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "com.castsprint.mac.capture.session")

    private(set) public var isRunning = false
    private(set) public var activeDevice: DiscoveredUSBDevice?
    public var currentQuality: CaptureQualityProfile = .automatic

    public override init() {
        super.init()
    }

    public func startCapture(device: DiscoveredUSBDevice, quality: CaptureQualityProfile = .automatic) throws {
        try sessionQueue.sync {
            stopCaptureInternal()

            self.currentQuality = quality
            let session = AVCaptureSession()
            session.beginConfiguration()

            // 1. Configure Video Input
            let avDevice = device.avDevice
            guard let vInput = try? AVCaptureDeviceInput(device: avDevice) else {
                session.commitConfiguration()
                throw NSError(domain: "CastSprint", code: -10, userInfo: [NSLocalizedDescriptionKey: "Failed to open video input for \(device.name)"])
            }

            if session.canAddInput(vInput) {
                session.addInput(vInput)
                self.videoInput = vInput
            } else {
                session.commitConfiguration()
                throw NSError(domain: "CastSprint", code: -11, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input to AVCaptureSession"])
            }

            // 2. Select Optimal Video Format based on Quality Profile
            configureFormat(for: avDevice, quality: quality)

            // 3. Configure Video Output
            let vOutput = AVCaptureVideoDataOutput()
            // Prefer NV12 (420v) for hardware Metal zero-copy decode
            vOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            ]
            vOutput.alwaysDiscardsLateVideoFrames = true
            vOutput.setSampleBufferDelegate(self, queue: videoQueue)

            if session.canAddOutput(vOutput) {
                session.addOutput(vOutput)
                self.videoOutput = vOutput
            }

            // 4. Audio Configuration
            // Note: Apple's AVCaptureDevice audio discovery for iOS devices ONLY exposes the physical voice microphone
            // (e.g. "iPhone Microphone") which captures ambient room noise, NOT internal digital game sound.
            // Pure internal game sound is routed via IDAM (Audio MIDI Setup) or ReplayKit .audioApp buffers.
            // We do NOT attach room microphone by default to avoid broadcasting room noise as game audio.
            let audioDiscovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external],
                mediaType: .audio,
                position: .unspecified
            )
            let baseName = device.name.replacingOccurrences(of: " Camera", with: "")
            let matchingAudio = audioDiscovery.devices.first { aDev in
                aDev.localizedName.contains(baseName) ||
                (aDev.modelID.contains("iPhone") || aDev.modelID.contains("iPad"))
            }

            if let matchingAudio = matchingAudio {
                NSLog("CastSprint: Detected iPhone microphone endpoint '%@' (Physical room mic, not internal game sound)", matchingAudio.localizedName)
            }


            let aOutput = AVCaptureAudioDataOutput()
            aOutput.setSampleBufferDelegate(self, queue: audioQueue)
            if session.canAddOutput(aOutput) {
                session.addOutput(aOutput)
                self.audioOutput = aOutput
            }

            session.commitConfiguration()
            session.startRunning()

            self.captureSession = session
            self.isRunning = true
            self.activeDevice = device

            registerSessionObservers()
            NSLog("CastSprint: Capture session started for %@ with profile %@", device.name, quality.rawValue)
        }
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
        self.audioInput = nil
        self.videoOutput = nil
        self.audioOutput = nil
        self.isRunning = false
        self.activeDevice = nil
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
        if output is AVCaptureVideoDataOutput {
            delegate?.captureSession(self, didOutputVideo: sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            delegate?.captureSession(self, didOutputAudio: sampleBuffer)
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Late frames discarded to prioritize real-time gameplay latency
    }
}
