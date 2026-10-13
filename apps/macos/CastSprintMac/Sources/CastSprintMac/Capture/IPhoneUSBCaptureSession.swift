// IPhoneUSBCaptureSession.swift — Native iPhone USB Capture (Zero Mobile App)
import Foundation
import AVFoundation
import CoreMedia

public final class IPhoneUSBCaptureSession: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate {

    public weak var sampleBufferSink: NativeSampleBufferInput?

    private var captureSession: AVCaptureSession?
    private let videoProcessingQueue = DispatchQueue(label: "com.castsprint.mac.usb.video", qos: .userInteractive)
    private let audioProcessingQueue = DispatchQueue(label: "com.castsprint.mac.usb.audio", qos: .userInteractive)

    private(set) public var isRunning = false
    private(set) public var currentDevice: ConnectedDevice?

    public override init() {
        super.init()
    }

    /// Starts capturing screen and audio from a connected USB iPhone
    public func startCapture(device: ConnectedDevice) throws {
        stopCapture()

        guard let avDevice = device.avDevice else {
            throw NSError(domain: "CastSprint", code: -1, userInfo: [NSLocalizedDescriptionKey: "No AVFoundation device available"])
        }

        CMIOManager.shared.enableScreenCaptureDevices()

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high

        // 1. Video Input
        let videoInput = try AVCaptureDeviceInput(device: avDevice)
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            throw NSError(domain: "CastSprint", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to add video input"])
        }

        // 2. Video Output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // 3. Audio Output (if device has audio capability)
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: audioProcessingQueue)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }

        session.commitConfiguration()
        session.startRunning()

        self.captureSession = session
        self.isRunning = true
        self.currentDevice = device
        NSLog("CastSprint: Started native iPhone USB capture for %@", device.name)
    }

    public func stopCapture() {
        guard isRunning, let session = captureSession else { return }
        session.stopRunning()
        self.captureSession = nil
        self.isRunning = false
        self.currentDevice = nil
        NSLog("CastSprint: Stopped iPhone USB capture")
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            sampleBufferSink?.onVideoSampleBuffer(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            sampleBufferSink?.onAudioSampleBuffer(sampleBuffer)
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Late frames dropped to prioritize zero latency
    }
}
