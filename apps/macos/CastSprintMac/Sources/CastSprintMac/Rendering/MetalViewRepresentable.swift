// MetalViewRepresentable.swift — SwiftUI MTKView Hosting Adapter
import SwiftUI
import MetalKit

public struct MetalViewRepresentable: NSViewRepresentable {
    public let renderer: MetalVideoRenderer

    public init(renderer: MetalVideoRenderer) {
        self.renderer = renderer
    }

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = renderer.device
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true // Display driven by incoming sample buffers

        if let metalLayer = mtkView.layer as? CAMetalLayer {
            renderer.attachLayer(metalLayer)
        }

        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        if let metalLayer = nsView.layer as? CAMetalLayer {
            renderer.attachLayer(metalLayer)
        }
    }
}
