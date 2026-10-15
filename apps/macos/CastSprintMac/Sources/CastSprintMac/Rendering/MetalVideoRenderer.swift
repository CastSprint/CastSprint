// MetalVideoRenderer.swift — Ultra-Low Latency Metal Video Renderer
import Foundation
import Metal
import MetalKit
import CoreVideo
import CoreMedia

public final class MetalVideoRenderer: NSObject, VideoRenderer {
    public let device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var samplerState: MTLSamplerState?
    private var yuvPipelineState: MTLRenderPipelineState?
    private var bgraPipelineState: MTLRenderPipelineState?

    public weak var metalLayer: CAMetalLayer?

    private(set) public var videoWidth: Int = 0
    private(set) public var videoHeight: Int = 0
    private(set) public var lastPixelBuffer: CVPixelBuffer?

    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    public func captureSnapshot() -> CGImage? {
        guard let pixelBuffer = lastPixelBuffer else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    public override init() {
        self.device = MTLCreateSystemDefaultDevice()
        super.init()

        guard let device = self.device else { return }
        self.commandQueue = device.makeCommandQueue()

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache

        // Sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.samplerState = device.makeSamplerState(descriptor: samplerDesc)

        buildPipelineStates(device: device)
    }

    private static let fallbackShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOutput {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOutput vertexShader(uint vertexID [[vertex_id]]) {
        const float2 positions[6] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2(-1.0,  1.0),
            float2( 1.0, -1.0),
            float2( 1.0,  1.0)
        };

        const float2 texCoords[6] = {
            float2(0.0, 1.0),
            float2(1.0, 1.0),
            float2(0.0, 0.0),
            float2(0.0, 0.0),
            float2(1.0, 1.0),
            float2(1.0, 0.0)
        };

        VertexOutput out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = texCoords[vertexID];
        return out;
    }

    fragment float4 yuvFragmentShader(
        VertexOutput in [[stage_in]],
        texture2d<float, access::sample> textureY [[texture(0)]],
        texture2d<float, access::sample> textureUV [[texture(1)]],
        sampler colorSampler [[sampler(0)]]
    ) {
        float y = textureY.sample(colorSampler, in.texCoord).r;
        float2 uv = textureUV.sample(colorSampler, in.texCoord).rg - float2(0.5, 0.5);

        float3 yuv = float3(y, uv.x, uv.y);
        float r = yuv.x + 1.5748 * yuv.z;
        float g = yuv.x - 0.1873 * yuv.y - 0.4681 * yuv.z;
        float b = yuv.x + 1.8556 * yuv.y;

        return float4(saturate(r), saturate(g), saturate(b), 1.0);
    }

    fragment float4 bgraFragmentShader(
        VertexOutput in [[stage_in]],
        texture2d<float, access::sample> colorTexture [[texture(0)]],
        sampler colorSampler [[sampler(0)]]
    ) {
        return colorTexture.sample(colorSampler, in.texCoord);
    }
    """

    private func buildPipelineStates(device: MTLDevice) {
        let library: MTLLibrary? = (try? device.makeDefaultLibrary(bundle: Bundle.module)) ??
                                   device.makeDefaultLibrary() ??
                                   (try? device.makeLibrary(source: Self.fallbackShaderSource, options: nil))

        guard let library = library else {
            NSLog("CastSprint: Fatal — Failed to compile or load Metal video shaders")
            return
        }

        let vertexFunc = library.makeFunction(name: "vertexShader")
        let yuvFragmentFunc = library.makeFunction(name: "yuvFragmentShader")
        let bgraFragmentFunc = library.makeFunction(name: "bgraFragmentShader")

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = yuvFragmentFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.yuvPipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDesc)

        let bgraDesc = MTLRenderPipelineDescriptor()
        bgraDesc.vertexFunction = vertexFunc
        bgraDesc.fragmentFunction = bgraFragmentFunc
        bgraDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.bgraPipelineState = try? device.makeRenderPipelineState(descriptor: bgraDesc)

        if self.yuvPipelineState != nil {
            NSLog("CastSprint: Successfully initialized Metal YUV BT.709 render pipeline")
        }
    }

    public func attachLayer(_ layer: CAMetalLayer) {
        self.metalLayer = layer
        layer.device = self.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
    }

    public func renderSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        renderPixelBuffer(pixelBuffer)
    }

    public func renderPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        guard let layer = metalLayer,
              let commandQueue = commandQueue,
              let textureCache = textureCache,
              let sampler = samplerState else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        self.videoWidth = width
        self.videoHeight = height
        self.lastPixelBuffer = pixelBuffer

        let pixelFormatType = CVPixelBufferGetPixelFormatType(pixelBuffer)

        guard let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            commandBuffer.commit()
            return
        }

        // Viewport aspect ratio preservation (Letterbox/Pillarbox)
        let drawableW = Double(drawable.texture.width)
        let drawableH = Double(drawable.texture.height)
        let videoAspect = Double(width) / Double(height)
        let viewAspect = drawableW / drawableH

        var vpX: Double = 0
        var vpY: Double = 0
        var vpW = drawableW
        var vpH = drawableH

        if viewAspect > videoAspect {
            // Pillarbox (black bars on left/right)
            vpW = drawableH * videoAspect
            vpX = (drawableW - vpW) / 2.0
        } else {
            // Letterbox (black bars on top/bottom)
            vpH = drawableW / videoAspect
            vpY = (drawableH - vpH) / 2.0
        }

        let viewport = MTLViewport(originX: vpX, originY: vpY, width: vpW, height: vpH, znear: 0.0, zfar: 1.0)
        encoder.setViewport(viewport)
        encoder.setFragmentSamplerState(sampler, index: 0)

        // NV12 Bi-Planar rendering
        if pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {

            guard let pipeline = yuvPipelineState else {
                encoder.endEncoding()
                commandBuffer.commit()
                return
            }

            var textureY: CVMetalTexture?
            var textureUV: CVMetalTexture?

            // Plane 0: Y (Luma)
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, pixelBuffer, nil,
                .r8Unorm, width, height, 0, &textureY
            )

            // Plane 1: UV (Chroma)
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, pixelBuffer, nil,
                .rg8Unorm, width / 2, height / 2, 1, &textureUV
            )

            if let yRef = textureY, let uvRef = textureUV,
               let texY = CVMetalTextureGetTexture(yRef),
               let texUV = CVMetalTextureGetTexture(uvRef) {

                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texY, index: 0)
                encoder.setFragmentTexture(texUV, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }

        } else if pixelFormatType == kCVPixelFormatType_32BGRA {
            // Direct BGRA Rendering
            guard let pipeline = bgraPipelineState else {
                encoder.endEncoding()
                commandBuffer.commit()
                return
            }

            var bgraTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, pixelBuffer, nil,
                .bgra8Unorm, width, height, 0, &bgraTexture
            )

            if let bgraRef = bgraTexture, let tex = CVMetalTextureGetTexture(bgraRef) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(tex, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    public func clear() {
        guard let layer = metalLayer,
              let commandQueue = commandQueue,
              let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)
        passDescriptor.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }
}
