// PipelineTelemetry.swift — Precise Multi-Stage Frame Pipeline Instrumentation
// CastSprint Multimedia Engineering
import Foundation
import CoreMedia
import CoreVideo

public final class PipelineTelemetry: @unchecked Sendable {
    public static let shared = PipelineTelemetry()

    // MARK: - Capture Stage Metrics
    public private(set) var captureSessionStarted: Bool = false
    public private(set) var captureSamplesReceived: UInt64 = 0
    public private(set) var validImageBuffersReceived: UInt64 = 0
    public private(set) var lastCaptureTimestamp: Double = 0.0
    public private(set) var capturePixelWidth: Int = 0
    public private(set) var capturePixelHeight: Int = 0
    public private(set) var capturePixelFormat: String = "None"
    public private(set) var capturePixelPlaneCount: Int = 0
    public private(set) var captureFps: Double = 0.0

    // MARK: - Render Stage Metrics
    public private(set) var rendererLayerAttached: Bool = false
    public private(set) var metalDeviceAvailable: Bool = false
    public private(set) var shaderLibraryLoaded: Bool = false
    public private(set) var pipelineStateReady: Bool = false
    public private(set) var drawablesAcquired: UInt64 = 0
    public private(set) var textureConversionSucceeded: UInt64 = 0
    public private(set) var renderCommandsEncoded: UInt64 = 0
    public private(set) var commandBuffersCommitted: UInt64 = 0
    public private(set) var commandBuffersCompleted: UInt64 = 0
    public private(set) var commandBuffersFailed: UInt64 = 0
    public private(set) var renderBackpressureDrops: UInt64 = 0
    public private(set) var renderedFramesCount: UInt64 = 0
    public private(set) var renderedFps: Double = 0.0
    public private(set) var mainPreviewFps: Double = 0.0
    public private(set) var gameplayWindowFps: Double = 0.0
    public private(set) var lastFramePresentedTimestamp: Double = 0.0
    public private(set) var lastRenderError: String? = nil

    // MARK: - Audio Stage Metrics
    public private(set) var audioSamplesReceived: UInt64 = 0
    public private(set) var audioSamplesDecoded: UInt64 = 0
    public private(set) var audioSamplesScheduled: UInt64 = 0
    public private(set) var audioPlaybackActive: Bool = false
    public private(set) var audioUnderruns: UInt64 = 0

    // MARK: - Calculation State
    private let lock = NSLock()
    private var captureFrameTimestamps: [Double] = []
    private var renderFrameTimestamps: [Double] = []
    private var gameplayFrameTimestamps: [Double] = []

    public init() {}

    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        captureSessionStarted = false
        captureSamplesReceived = 0
        validImageBuffersReceived = 0
        lastCaptureTimestamp = 0.0
        capturePixelWidth = 0
        capturePixelHeight = 0
        capturePixelFormat = "None"
        capturePixelPlaneCount = 0
        captureFps = 0.0

        drawablesAcquired = 0
        textureConversionSucceeded = 0
        renderCommandsEncoded = 0
        commandBuffersCommitted = 0
        commandBuffersCompleted = 0
        commandBuffersFailed = 0
        renderBackpressureDrops = 0
        renderedFramesCount = 0
        renderedFps = 0.0
        mainPreviewFps = 0.0
        gameplayWindowFps = 0.0
        lastFramePresentedTimestamp = 0.0
        lastRenderError = nil

        audioSamplesReceived = 0
        audioSamplesDecoded = 0
        audioSamplesScheduled = 0
        audioPlaybackActive = false
        audioUnderruns = 0

        captureFrameTimestamps.removeAll(keepingCapacity: true)
        renderFrameTimestamps.removeAll(keepingCapacity: true)
        gameplayFrameTimestamps.removeAll(keepingCapacity: true)
    }

    // MARK: - Capture Instrumentation
    public func recordCaptureSessionStarted(_ started: Bool) {
        lock.lock()
        captureSessionStarted = started
        lock.unlock()
    }

    public func recordCaptureSample(buffer: CMSampleBuffer?) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        defer { lock.unlock() }

        captureSamplesReceived += 1
        lastCaptureTimestamp = now

        guard let sample = buffer, CMSampleBufferIsValid(sample) else { return }

        if let pixelBuffer = CMSampleBufferGetImageBuffer(sample) {
            validImageBuffersReceived += 1
            capturePixelWidth = CVPixelBufferGetWidth(pixelBuffer)
            capturePixelHeight = CVPixelBufferGetHeight(pixelBuffer)
            capturePixelPlaneCount = CVPixelBufferGetPlaneCount(pixelBuffer)

            let formatType = CVPixelBufferGetPixelFormatType(pixelBuffer)
            capturePixelFormat = fourCCToString(formatType)
        }

        // Rolling 1-second capture FPS window
        captureFrameTimestamps.append(now)
        let cutoff = now - 1.0
        while let first = captureFrameTimestamps.first, first < cutoff {
            captureFrameTimestamps.removeFirst()
        }
        captureFps = Double(captureFrameTimestamps.count)
    }

    // MARK: - Render Instrumentation
    public func setRendererLayerAttached(_ attached: Bool) {
        lock.lock()
        rendererLayerAttached = attached
        lock.unlock()
    }

    public func setMetalDeviceAvailable(_ available: Bool) {
        lock.lock()
        metalDeviceAvailable = available
        lock.unlock()
    }

    public func setPipelineReady(_ ready: Bool, shaderLoaded: Bool) {
        lock.lock()
        pipelineStateReady = ready
        shaderLibraryLoaded = shaderLoaded
        lock.unlock()
    }

    public func recordDrawableAcquired() {
        lock.lock()
        drawablesAcquired += 1
        lock.unlock()
    }

    public func recordTextureConversionSuccess() {
        lock.lock()
        textureConversionSucceeded += 1
        lock.unlock()
    }

    public func recordRenderCommandsEncoded() {
        lock.lock()
        renderCommandsEncoded += 1
        lock.unlock()
    }

    public func recordCommandBufferCommitted() {
        lock.lock()
        commandBuffersCommitted += 1
        lock.unlock()
    }

    public func recordCommandBufferCompleted() {
        lock.lock()
        commandBuffersCompleted += 1
        lock.unlock()
    }

    public func recordRenderBackpressureDrop() {
        lock.lock()
        renderBackpressureDrops += 1
        lock.unlock()
    }

    public func recordFramePresented(output: RendererOutputTarget = .mainPreview) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        defer { lock.unlock() }

        renderedFramesCount += 1
        lastFramePresentedTimestamp = now
        lastRenderError = nil

        // Rolling 1-second render FPS window
        var timestamps = output == .mainPreview ? renderFrameTimestamps : gameplayFrameTimestamps
        timestamps.append(now)
        let cutoff = now - 1.0
        while let first = timestamps.first, first < cutoff {
            timestamps.removeFirst()
        }
        if output == .mainPreview {
            renderFrameTimestamps = timestamps
            mainPreviewFps = Double(timestamps.count)
            renderedFps = mainPreviewFps
        } else {
            gameplayFrameTimestamps = timestamps
            gameplayWindowFps = Double(timestamps.count)
        }
    }

    public func recordRenderError(_ message: String) {
        lock.lock()
        commandBuffersFailed += 1
        lastRenderError = message
        lock.unlock()
    }

    // MARK: - Audio Instrumentation
    public func recordAudioSample() {
        lock.lock()
        audioSamplesReceived += 1
        audioPlaybackActive = true
        lock.unlock()
    }

    public func recordAudioUnderrun() {
        lock.lock()
        audioUnderruns += 1
        lock.unlock()
    }

    private func fourCCToString(_ code: OSType) -> String {
        let chars: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        var str = ""
        for c in chars {
            if c >= 32 && c <= 126 {
                str.append(Character(UnicodeScalar(c)))
            } else {
                return String(format: "0x%08X", code)
            }
        }
        return str
    }
}
