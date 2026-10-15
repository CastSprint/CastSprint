// MetalVideoRenderer.swift — frame-driven, multi-target CAMetalLayer renderer
import Foundation
import Metal
import QuartzCore
import CoreVideo
import CoreMedia
import CoreImage
import ImageIO

public enum RendererOutputTarget: String, Sendable {
    case mainPreview
    case gameplayWindow
}

private final class WeakMetalLayer {
    weak var value: CAMetalLayer?
    let output: RendererOutputTarget
    init(_ value: CAMetalLayer, output: RendererOutputTarget) {
        self.value = value
        self.output = output
    }
}

public final class MetalVideoRenderer: NSObject, VideoRenderer, @unchecked Sendable {
    public static let maximumInFlightCommandBuffers = 3
    public let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private let samplerState: MTLSamplerState?
    private let ciContext: CIContext?
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var yuvPipelineState: MTLRenderPipelineState?
    private var bgraPipelineState: MTLRenderPipelineState?

    private let stateLock = NSLock()
    // Two windows can submit work for the same source frame. Three permits keep
    // both outputs responsive while placing a hard ceiling on retained drawables,
    // pixel buffers, Core Image graphs, and command buffers.
    private let inFlightSemaphore = DispatchSemaphore(value: maximumInFlightCommandBuffers)
    private var targets: [WeakMetalLayer] = []
    private var latestPixelBuffer: CVPixelBuffer?
    private var presentedFrame = false
    private var pendingDiagnosticCapture: (directory: URL, completion: (Result<URL, Error>) -> Void)?
    private let diagnosticQueue = DispatchQueue(label: "com.castsprint.mac.diagnostic-frame", qos: .utility)

    public private(set) var videoWidth = 0
    public private(set) var videoHeight = 0
    public var onFramePresented: (() -> Void)?
    public var onSourceDimensionsChanged: ((Int, Int) -> Void)?

    public var hasPresentedFrame: Bool {
        stateLock.withLock { presentedFrame }
    }

    public override init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.commandQueue = device?.makeCommandQueue()

        if let device {
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
            self.textureCache = cache

            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.sAddressMode = .clampToEdge
            descriptor.tAddressMode = .clampToEdge
            self.samplerState = device.makeSamplerState(descriptor: descriptor)
            self.ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            self.samplerState = nil
            self.ciContext = nil
        }

        super.init()
        PipelineTelemetry.shared.setMetalDeviceAvailable(device != nil)
        if let device { buildPipelineStates(device: device) }
    }

    public func attachLayer(_ layer: CAMetalLayer, output: RendererOutputTarget = .mainPreview) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        // Core Image's GPU-backed 2vuy conversion writes directly into the
        // drawable texture, which requires a non-framebuffer-only layer.
        layer.framebufferOnly = false
        layer.maximumDrawableCount = 2
        layer.allowsNextDrawableTimeout = true
        layer.isOpaque = true
        stateLock.withLock {
            targets.removeAll { $0.value == nil }
            if !targets.contains(where: { $0.value === layer }) {
                targets.append(WeakMetalLayer(layer, output: output))
            }
            PipelineTelemetry.shared.setRendererLayerAttached(!targets.isEmpty)
        }
    }

    public func detachLayer(_ layer: CAMetalLayer) {
        stateLock.withLock {
            targets.removeAll { $0.value == nil || $0.value === layer }
            PipelineTelemetry.shared.setRendererLayerAttached(!targets.isEmpty)
        }
    }

    public func renderSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            PipelineTelemetry.shared.recordRenderError("Video sample has no valid image buffer")
            return
        }
        renderPixelBuffer(pixelBuffer)
    }

    public func renderPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            PipelineTelemetry.shared.recordRenderError("Video frame has invalid dimensions")
            return
        }

        let result: (targets: [(CAMetalLayer, RendererOutputTarget)], dimensionsChanged: Bool, diagnostic: (directory: URL, completion: (Result<URL, Error>) -> Void)?) = stateLock.withLock {
            let dimensionsChanged = videoWidth != width || videoHeight != height
            videoWidth = width
            videoHeight = height
            latestPixelBuffer = pixelBuffer
            let diagnostic = pendingDiagnosticCapture
            pendingDiagnosticCapture = nil
            targets.removeAll { $0.value == nil }
            return (targets.compactMap { target in target.value.map { ($0, target.output) } }, dimensionsChanged, diagnostic)
        }

        if result.dimensionsChanged {
            DispatchQueue.main.async { [weak self] in
                self?.onSourceDimensionsChanged?(width, height)
            }
        }

        if let diagnostic = result.diagnostic {
            exportDiagnosticFrame(pixelBuffer, to: diagnostic.directory, completion: diagnostic.completion)
        }

        guard !result.targets.isEmpty else {
            PipelineTelemetry.shared.recordRenderError("No visible CAMetalLayer is attached")
            return
        }

        for (layer, output) in result.targets {
            render(
                pixelBuffer,
                width: width,
                height: height,
                to: layer,
                output: output
            )
        }
    }

    /// Opt-in CPU/Core Image inspection path. This is never used for live presentation.
    public func captureSnapshot() -> CGImage? {
        let pixelBuffer = stateLock.withLock { latestPixelBuffer }
        guard let pixelBuffer else { return nil }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(image, from: image.extent)
    }

    public func exportDiagnosticSnapshot(to url: URL) -> Bool {
        guard let image = captureSnapshot(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Arms a single-frame, opt-in diagnostic export. The next real source frame is
    /// written once; no screen content is retained or continuously captured.
    public func requestDiagnosticCapture(
        in directory: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        stateLock.withLock {
            pendingDiagnosticCapture = (directory, completion)
        }
    }

    public func clear() {
        let layers = stateLock.withLock { () -> [CAMetalLayer] in
            latestPixelBuffer = nil
            presentedFrame = false
            targets.removeAll { $0.value == nil }
            return targets.compactMap(\.value)
        }
        for layer in layers { clear(layer) }
        if let textureCache { CVMetalTextureCacheFlush(textureCache, 0) }
    }

    private func render(
        _ pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        to layer: CAMetalLayer,
        output: RendererOutputTarget
    ) {
        guard inFlightSemaphore.wait(timeout: .now()) == .success else {
            PipelineTelemetry.shared.recordRenderBackpressureDrop()
            return
        }
        var submitted = false
        defer {
            if !submitted { inFlightSemaphore.signal() }
        }

        guard let commandQueue, let textureCache, let samplerState else {
            PipelineTelemetry.shared.recordRenderError("Metal renderer resources are unavailable")
            return
        }
        guard layer.drawableSize.width > 1, layer.drawableSize.height > 1 else {
            PipelineTelemetry.shared.recordRenderError("Metal drawable size is empty")
            return
        }
        guard let drawable = layer.nextDrawable() else {
            PipelineTelemetry.shared.recordRenderError("CAMetalLayer could not provide a drawable")
            return
        }
        PipelineTelemetry.shared.recordDrawableAcquired()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            PipelineTelemetry.shared.recordRenderError("Metal command buffer creation failed")
            return
        }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if format == kCVPixelFormatType_422YpCbCr8 {
            submitted = renderPacked422(
                pixelBuffer,
                width: width,
                height: height,
                drawable: drawable,
                commandBuffer: commandBuffer,
                output: output
            )
            return
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            PipelineTelemetry.shared.recordRenderError("Metal render encoder creation failed")
            return
        }

        let drawableWidth = Double(drawable.texture.width)
        let drawableHeight = Double(drawable.texture.height)
        let videoAspect = Double(width) / Double(height)
        let viewAspect = drawableWidth / drawableHeight
        var viewport = MTLViewport(originX: 0, originY: 0, width: drawableWidth, height: drawableHeight, znear: 0, zfar: 1)
        if viewAspect > videoAspect {
            viewport.width = drawableHeight * videoAspect
            viewport.originX = (drawableWidth - viewport.width) / 2
        } else {
            viewport.height = drawableWidth / videoAspect
            viewport.originY = (drawableHeight - viewport.height) / 2
        }
        encoder.setViewport(viewport)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        var encoded = false
        var retainedTextures: [CVMetalTexture] = []

        if format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
           let pipeline = yuvPipelineState {
            var yRef: CVMetalTexture?
            var uvRef: CVMetalTexture?
            let yStatus = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, pixelBuffer, nil, .r8Unorm,
                CVPixelBufferGetWidthOfPlane(pixelBuffer, 0), CVPixelBufferGetHeightOfPlane(pixelBuffer, 0), 0, &yRef)
            let uvStatus = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, pixelBuffer, nil, .rg8Unorm,
                CVPixelBufferGetWidthOfPlane(pixelBuffer, 1), CVPixelBufferGetHeightOfPlane(pixelBuffer, 1), 1, &uvRef)
            if yStatus == kCVReturnSuccess, uvStatus == kCVReturnSuccess,
               let yRef, let uvRef,
               let yTexture = CVMetalTextureGetTexture(yRef),
               let uvTexture = CVMetalTextureGetTexture(uvRef) {
                retainedTextures = [yRef, uvRef]
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(yTexture, index: 0)
                encoder.setFragmentTexture(uvTexture, index: 1)
                encoded = true
            }
        } else if format == kCVPixelFormatType_32BGRA, let pipeline = bgraPipelineState {
            var bgraRef: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm,
                width, height, 0, &bgraRef)
            if status == kCVReturnSuccess, let bgraRef,
               let texture = CVMetalTextureGetTexture(bgraRef) {
                retainedTextures = [bgraRef]
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture, index: 0)
                encoded = true
            }
        } else {
            PipelineTelemetry.shared.recordRenderError(String(format: "Unsupported pixel format 0x%08X", format))
        }

        guard encoded else {
            encoder.endEncoding()
            PipelineTelemetry.shared.recordRenderError("Pixel buffer could not be converted to Metal textures")
            return
        }

        PipelineTelemetry.shared.recordTextureConversionSuccess()
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        PipelineTelemetry.shared.recordRenderCommandsEncoded()
        encoder.endEncoding()
        commandBuffer.present(drawable)
        let permit = inFlightSemaphore
        commandBuffer.addCompletedHandler { [weak self] buffer in
            defer { permit.signal() }
            _ = retainedTextures
            guard let self else { return }
            if buffer.status == .completed {
                PipelineTelemetry.shared.recordCommandBufferCompleted()
                let firstPresentation = self.stateLock.withLock { () -> Bool in
                    let first = !self.presentedFrame
                    self.presentedFrame = true
                    return first
                }
                PipelineTelemetry.shared.recordFramePresented(output: output)
                if firstPresentation {
                    DispatchQueue.main.async { [weak self] in self?.onFramePresented?() }
                }
            } else {
                PipelineTelemetry.shared.recordRenderError(buffer.error?.localizedDescription ?? "Metal command buffer failed")
            }
        }
        commandBuffer.commit()
        submitted = true
        PipelineTelemetry.shared.recordCommandBufferCommitted()
    }

    /// Converts native iPhone UYVY/`2vuy` with Core Image's Metal backend.
    /// Core Image reads the buffer's YCbCr matrix/range/primaries attachments,
    /// avoiding guessed byte swizzles and writing directly to the drawable.
    @discardableResult
    private func renderPacked422(
        _ pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        drawable: CAMetalDrawable,
        commandBuffer: MTLCommandBuffer,
        output: RendererOutputTarget
    ) -> Bool {
        guard let ciContext else {
            PipelineTelemetry.shared.recordRenderError("PIPELINE_UNAVAILABLE: Metal Core Image context is unavailable for 2vuy")
            return false
        }

        let destination = CGRect(
            x: 0,
            y: 0,
            width: drawable.texture.width,
            height: drawable.texture.height
        )
        let scale = min(destination.width / CGFloat(width), destination.height / CGFloat(height))
        let fittedWidth = CGFloat(width) * scale
        let fittedHeight = CGFloat(height) * scale
        let originX = (destination.width - fittedWidth) / 2
        let originY = (destination.height - fittedHeight) / 2

        var source = CIImage(cvPixelBuffer: pixelBuffer)
        source = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        source = source.transformed(by: CGAffineTransform(translationX: originX, y: originY))
        let background = CIImage(color: CIColor(red: 0.05, green: 0.07, blue: 0.09)).cropped(to: destination)
        let composedImage = source.composited(over: background)

        ciContext.render(
            composedImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: destination,
            colorSpace: outputColorSpace
        )
        PipelineTelemetry.shared.recordTextureConversionSuccess()
        PipelineTelemetry.shared.recordRenderCommandsEncoded()
        commandBuffer.present(drawable)
        let permit = inFlightSemaphore
        commandBuffer.addCompletedHandler { [weak self] buffer in
            defer { permit.signal() }
            guard let self else { return }
            if buffer.status == .completed {
                PipelineTelemetry.shared.recordCommandBufferCompleted()
                let firstPresentation = self.stateLock.withLock { () -> Bool in
                    let first = !self.presentedFrame
                    self.presentedFrame = true
                    return first
                }
                PipelineTelemetry.shared.recordFramePresented(output: output)
                if firstPresentation {
                    DispatchQueue.main.async { [weak self] in self?.onFramePresented?() }
                }
            } else {
                PipelineTelemetry.shared.recordRenderError(
                    "GPU_COMMAND_FAILED: \(buffer.error?.localizedDescription ?? "2vuy conversion failed")"
                )
            }
        }
        commandBuffer.commit()
        PipelineTelemetry.shared.recordCommandBufferCommitted()
        return true
    }

    private func clear(_ layer: CAMetalLayer) {
        guard let commandQueue, let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func exportDiagnosticFrame(
        _ pixelBuffer: CVPixelBuffer,
        to directory: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        diagnosticQueue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let formatter = ISO8601DateFormatter()
                let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let pngURL = directory.appendingPathComponent("source-frame-\(stamp).png")
                let metadataURL = directory.appendingPathComponent("source-frame-\(stamp).txt")
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext(options: [.cacheIntermediates: false])
                guard let image = context.createCGImage(ciImage, from: ciImage.extent),
                      let destination = CGImageDestinationCreateWithURL(pngURL as CFURL, "public.png" as CFString, 1, nil)
                else { throw DiagnosticCaptureError.imageConversionFailed }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else {
                    throw DiagnosticCaptureError.imageWriteFailed
                }
                let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
                let metadata = """
                capturedAt=\(formatter.string(from: Date()))
                width=\(CVPixelBufferGetWidth(pixelBuffer))
                height=\(CVPixelBufferGetHeight(pixelBuffer))
                pixelFormat=\(Self.fourCC(format))
                planeCount=\(CVPixelBufferGetPlaneCount(pixelBuffer))
                """
                try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
                completion(.success(pngURL))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func fourCC(_ value: OSType) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> OSType($0)) & 0xff) }
        if bytes.allSatisfy({ (32...126).contains($0) }) {
            return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", value)
        }
        return String(format: "0x%08X", value)
    }

    private func buildPipelineStates(device: MTLDevice) {
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let vertex = library.makeFunction(name: "vertexShader")
            let yuv = library.makeFunction(name: "yuvFragmentShader")
            let bgra = library.makeFunction(name: "bgraFragmentShader")

            let yuvDescriptor = MTLRenderPipelineDescriptor()
            yuvDescriptor.vertexFunction = vertex
            yuvDescriptor.fragmentFunction = yuv
            yuvDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            yuvPipelineState = try device.makeRenderPipelineState(descriptor: yuvDescriptor)

            let bgraDescriptor = MTLRenderPipelineDescriptor()
            bgraDescriptor.vertexFunction = vertex
            bgraDescriptor.fragmentFunction = bgra
            bgraDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            bgraPipelineState = try device.makeRenderPipelineState(descriptor: bgraDescriptor)
            PipelineTelemetry.shared.setPipelineReady(true, shaderLoaded: true)
        } catch {
            PipelineTelemetry.shared.setPipelineReady(false, shaderLoaded: false)
            PipelineTelemetry.shared.recordRenderError("Metal shader pipeline failed: \(error.localizedDescription)")
        }
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VertexOutput { float4 position [[position]]; float2 texCoord; };
    vertex VertexOutput vertexShader(uint id [[vertex_id]]) {
        const float2 p[6] = { {-1,-1}, {1,-1}, {-1,1}, {-1,1}, {1,-1}, {1,1} };
        const float2 t[6] = { {0,1}, {1,1}, {0,0}, {0,0}, {1,1}, {1,0} };
        VertexOutput out; out.position = float4(p[id], 0, 1); out.texCoord = t[id]; return out;
    }
    fragment float4 yuvFragmentShader(VertexOutput in [[stage_in]],
        texture2d<float> yTexture [[texture(0)]], texture2d<float> uvTexture [[texture(1)]],
        sampler s [[sampler(0)]]) {
        float y = yTexture.sample(s, in.texCoord).r;
        float2 uv = uvTexture.sample(s, in.texCoord).rg - float2(0.5);
        return float4(saturate(y + 1.5748 * uv.y),
                      saturate(y - 0.1873 * uv.x - 0.4681 * uv.y),
                      saturate(y + 1.8556 * uv.x), 1);
    }
    fragment float4 bgraFragmentShader(VertexOutput in [[stage_in]],
        texture2d<float> texture [[texture(0)]], sampler s [[sampler(0)]]) {
        return texture.sample(s, in.texCoord);
    }
    """
}

private enum DiagnosticCaptureError: LocalizedError {
    case imageConversionFailed
    case imageWriteFailed

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed: return "Core Image could not convert the source frame"
        case .imageWriteFailed: return "The diagnostic PNG could not be finalized"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
