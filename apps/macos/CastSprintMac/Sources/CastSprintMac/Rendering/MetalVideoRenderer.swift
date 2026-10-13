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

    public weak var metalLayer: CAMetalLayer?

    public override init() {
        self.device = MTLCreateSystemDefaultDevice()
        super.init()

        if let device = device {
            self.commandQueue = device.makeCommandQueue()
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
            self.textureCache = cache
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
              let textureCache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var imageTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &imageTexture
        )

        guard status == kCVReturnSuccess,
              let textureRef = imageTexture,
              let srcTexture = CVMetalTextureGetTexture(textureRef),
              let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // Fast blit / pass from decoded source texture to display drawable
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()
        let origin = MTLOrigin(x: 0, y: 0, z: 0)
        let size = MTLSize(width: min(width, drawable.texture.width),
                           height: min(height, drawable.texture.height),
                           depth: 1)

        blitEncoder?.copy(from: srcTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize: size,
                          to: drawable.texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
        blitEncoder?.endEncoding()

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
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0) // Dark theme
        passDescriptor.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
