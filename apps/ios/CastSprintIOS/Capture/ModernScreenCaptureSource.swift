// ModernScreenCaptureSource.swift — Next-Gen ScreenCaptureKit Adapter for iOS
import Foundation
import CoreMedia
import CoreVideo
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

public final class ModernScreenCaptureSource: NSObject, ScreenCaptureSource {
    public weak var delegate: ScreenCaptureSourceDelegate?

    public private(set) var isCapturing: Bool = false
    public var isMicrophoneEnabled: Bool = false
    public private(set) var currentOrientation: CaptureOrientation = .portrait

    #if canImport(ScreenCaptureKit)
    private var activeStream: Any? // SCStream when available
    private var activeConfiguration: Any? // SCStreamConfiguration when available
    #endif

    public override init() {
        super.init()
    }

    public func requestCaptureAuthorization(completion: @escaping (Result<Bool, CaptureError>) -> Void) {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, macOS 14.0, *) {
            // ScreenCaptureKit on supported iOS versions uses SCContentSharingPicker
            DispatchQueue.main.async {
                SCContentSharingPicker.shared.isActive = true
                completion(.success(true))
            }
            return
        }
        #endif
        completion(.failure(.unsupportedOS))
    }

    public func startCapture() throws {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, macOS 14.0, *) {
            guard !isCapturing else { return }

            // Obtain shareable content
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
                guard let self = self else { return }
                if let error = error {
                    self.delegate?.captureSource(self, didEncounterError: .internalError(error.localizedDescription))
                    return
                }

                guard let display = content?.displays.first else {
                    self.delegate?.captureSource(self, didEncounterError: .internalError("No active display found"))
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60 FPS
                config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                config.capturesAudio = true
                config.showsCursor = true

                do {
                    let stream = SCStream(filter: filter, configuration: config, delegate: self)
                    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.castsprint.ios.sck.video", qos: .userInteractive))
                    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.castsprint.ios.sck.audio", qos: .userInteractive))

                    stream.startCapture { [weak self] startError in
                        guard let self = self else { return }
                        if let startError = startError {
                            self.delegate?.captureSource(self, didEncounterError: .internalError(startError.localizedDescription))
                        } else {
                            self.activeStream = stream
                            self.activeConfiguration = config
                            self.isCapturing = true
                        }
                    }
                } catch {
                    self.delegate?.captureSource(self, didEncounterError: .internalError(error.localizedDescription))
                }
            }
            return
        }
        #endif
        throw CaptureError.unsupportedOS
    }

    public func pauseCapture() {
        isCapturing = false
        delegate?.captureSourceDidPause(self)
    }

    public func resumeCapture() {
        isCapturing = true
        delegate?.captureSourceDidResume(self)
    }

    public func stopCapture() {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, macOS 14.0, *) {
            if let stream = activeStream as? SCStream {
                stream.stopCapture { [weak self] _ in
                    guard let self = self else { return }
                    self.activeStream = nil
                    self.isCapturing = false
                    self.delegate?.captureSourceDidStop(self)
                }
                return
            }
        }
        #endif
        isCapturing = false
        delegate?.captureSourceDidStop(self)
    }
}

#if canImport(ScreenCaptureKit)
@available(iOS 27.0, macOS 14.0, *)
extension ModernScreenCaptureSource: SCStreamDelegate, SCStreamOutput {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        isCapturing = false
        delegate?.captureSource(self, didEncounterError: .internalError(error.localizedDescription))
        delegate?.captureSourceDidStop(self)
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isCapturing else { return }

        switch type {
        case .screen:
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                delegate?.captureSource(self, didOutputVideo: pixelBuffer, presentationTime: pts)
            }

        case .audio:
            delegate?.captureSource(self, didOutputApplicationAudio: sampleBuffer)

        case .microphone:
            if isMicrophoneEnabled {
                delegate?.captureSource(self, didOutputMicrophoneAudio: sampleBuffer)
            }

        @unknown default:
            break
        }
    }
}
#endif
