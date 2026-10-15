// MetalViewRepresentable.swift — SwiftUI adapter for the frame-driven CAMetalLayer renderer
import SwiftUI
import AppKit
import Metal

/// One presentation owner: this view's backing layer is the CAMetalLayer.
/// There is no child layer and no competing Core Graphics draw path.
public final class MirrorNativeDisplayView: NSView {
    public weak var renderer: MetalVideoRenderer?
    public let outputTarget: RendererOutputTarget

    public override var wantsUpdateLayer: Bool { true }
    public override var isOpaque: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }

    public init(renderer: MetalVideoRenderer, outputTarget: RendererOutputTarget = .mainPreview) {
        self.renderer = renderer
        self.outputTarget = outputTarget
        super.init(frame: .zero)
        wantsLayer = true
        configureLayer()
    }

    public required init?(coder: NSCoder) {
        self.outputTarget = .mainPreview
        super.init(coder: coder)
        wantsLayer = true
        configureLayer()
    }

    deinit {
        if let metalLayer = layer as? CAMetalLayer {
            renderer?.detachLayer(metalLayer)
        }
    }

    private func configureLayer() {
        guard let metalLayer = layer as? CAMetalLayer else { return }
        metalLayer.device = renderer?.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = CGColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        metalLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        renderer?.attachLayer(metalLayer, output: outputTarget)
        updateDrawableSize()
    }

    public override func layout() {
        super.layout()
        updateDrawableSize()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let metalLayer = layer as? CAMetalLayer else { return }
        if window == nil {
            renderer?.detachLayer(metalLayer)
        } else {
            configureLayer()
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        guard let metalLayer = layer as? CAMetalLayer else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: max(bounds.width * scale, 1),
            height: max(bounds.height * scale, 1)
        )
    }
}

public struct MetalViewRepresentable: NSViewRepresentable {
    public let renderer: MetalVideoRenderer

    public init(renderer: MetalVideoRenderer) {
        self.renderer = renderer
    }

    public func makeNSView(context: Context) -> MirrorNativeDisplayView {
        MirrorNativeDisplayView(renderer: renderer)
    }

    public func updateNSView(_ nsView: MirrorNativeDisplayView, context: Context) {
        nsView.renderer = renderer
        if let metalLayer = nsView.layer as? CAMetalLayer {
            renderer.attachLayer(metalLayer, output: nsView.outputTarget)
        }
    }

    public static func dismantleNSView(_ nsView: MirrorNativeDisplayView, coordinator: ()) {
        guard let metalLayer = nsView.layer as? CAMetalLayer else { return }
        nsView.renderer?.detachLayer(metalLayer)
    }
}
