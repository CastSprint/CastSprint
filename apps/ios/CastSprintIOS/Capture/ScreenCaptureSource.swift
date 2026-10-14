// ScreenCaptureSource.swift — Unified Screen & Audio Capture Interface for iOS
import Foundation
import CoreMedia
import CoreVideo

public enum CaptureOrientation: Int {
    case portrait = 0
    case landscapeLeft = 90
    case upsideDown = 180
    case landscapeRight = 270
}

public enum CaptureError: Error, LocalizedError {
    case permissionDenied
    case systemInterrupted
    case protectedContentBlocked
    case unsupportedOS
    case memoryPressure
    case internalError(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen capture permission was denied by the user."
        case .systemInterrupted:
            return "Screen capture was interrupted by an incoming call or system alert."
        case .protectedContentBlocked:
            return "Protected DRM content (HDCP/FairPlay) cannot be captured."
        case .unsupportedOS:
            return "The selected capture technology is not supported on this iOS version."
        case .memoryPressure:
            return "Capture process exceeded system memory thresholds."
        case .internalError(let msg):
            return "Capture error: \(msg)"
        }
    }
}

public protocol ScreenCaptureSourceDelegate: AnyObject {
    func captureSource(_ source: ScreenCaptureSource, didOutputVideo pixelBuffer: CVPixelBuffer, presentationTime: CMTime)
    func captureSource(_ source: ScreenCaptureSource, didOutputApplicationAudio sampleBuffer: CMSampleBuffer)
    func captureSource(_ source: ScreenCaptureSource, didOutputMicrophoneAudio sampleBuffer: CMSampleBuffer)
    func captureSource(_ source: ScreenCaptureSource, didChangeOrientation orientation: CaptureOrientation)
    func captureSource(_ source: ScreenCaptureSource, didEncounterError error: CaptureError)
    func captureSourceDidPause(_ source: ScreenCaptureSource)
    func captureSourceDidResume(_ source: ScreenCaptureSource)
    func captureSourceDidStop(_ source: ScreenCaptureSource)
}

public protocol ScreenCaptureSource: AnyObject {
    var delegate: ScreenCaptureSourceDelegate? { get set }
    var isCapturing: Bool { get }
    var isMicrophoneEnabled: Bool { get set }
    var currentOrientation: CaptureOrientation { get }

    func requestCaptureAuthorization(completion: @escaping (Result<Bool, CaptureError>) -> Void)
    func startCapture() throws
    func pauseCapture()
    func resumeCapture()
    func stopCapture()
}
