// OBSGameplayWindowController.swift — Dedicated Clean Feed Window for OBS Studio Capture
// CastSprint Multimedia Engineering
import AppKit

public enum CreatorOrientationMode: String, CaseIterable {
    case automatic = "Auto Orientation"
    case portrait = "Lock Portrait"
    case landscape = "Lock Landscape"
    case manual = "Manual Window"
}

public enum CreatorCanvasPreset: String, CaseIterable {
    case sourceNative = "Source Native"
    case landscape1080 = "1920 × 1080"
    case landscape720 = "1280 × 720"
    case portrait1080 = "1080 × 1920"
    case portrait720 = "720 × 1280"

    var aspectSize: NSSize? {
        switch self {
        case .sourceNative: return nil
        case .landscape1080: return NSSize(width: 1920, height: 1080)
        case .landscape720: return NSSize(width: 1280, height: 720)
        case .portrait1080: return NSSize(width: 1080, height: 1920)
        case .portrait720: return NSSize(width: 720, height: 1280)
        }
    }
}

@MainActor
public final class OBSGameplayWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = OBSGameplayWindowController()

    private var displayView: MirrorNativeDisplayView?
    private var lastSourceSize: NSSize = .zero
    private var userResizedWindow = false
    public var automaticallyResizeForOrientation = true
    public private(set) var orientationMode: CreatorOrientationMode = .automatic
    public private(set) var canvasPreset: CreatorCanvasPreset = .sourceNative

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CastSprint — Gameplay"
        window.identifier = NSUserInterfaceItemIdentifier("CastSprintGameplayWindow")
        window.contentMinSize = NSSize(width: 320, height: 180)
        window.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)

        super.init(window: window)
        window.delegate = self

        let renderer = MirroringCoordinator.shared.videoRenderer
        let view = MirrorNativeDisplayView(renderer: renderer, outputTarget: .gameplayWindow)
        self.displayView = view
        window.contentView = view
        view.setRenderingEnabled(false)

        renderer.onSourceDimensionsChanged = { [weak self] width, height in
            self?.sourceDimensionsDidChange(width: width, height: height)
        }

    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func toggleWindow() {
        if window?.isVisible == true {
            displayView?.setRenderingEnabled(false)
            window?.orderOut(nil)
        } else {
            showWindow(nil)
            displayView?.setRenderingEnabled(true)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    public func windowWillClose(_ notification: Notification) {
        displayView?.setRenderingEnabled(false)
    }

    public func windowDidResize(_ notification: Notification) {
        guard window?.inLiveResize == true else { return }
        userResizedWindow = true
    }

    public func setOrientationMode(_ mode: CreatorOrientationMode) {
        orientationMode = mode
        automaticallyResizeForOrientation = mode != .manual
        userResizedWindow = mode == .manual
        if lastSourceSize != .zero { resizeContentToSourceAspect(lastSourceSize) }
    }

    public func setCanvasPreset(_ preset: CreatorCanvasPreset) {
        canvasPreset = preset
        if lastSourceSize != .zero { resizeContentToSourceAspect(lastSourceSize) }
    }

    private func sourceDimensionsDidChange(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        let size = NSSize(width: width, height: height)
        guard size != lastSourceSize else { return }
        let orientationChanged = (lastSourceSize.width > lastSourceSize.height) != (size.width > size.height)
        lastSourceSize = size

        guard automaticallyResizeForOrientation, (!userResizedWindow || orientationChanged) else { return }
        resizeContentToSourceAspect(size)
        userResizedWindow = false
    }

    private func resizeContentToSourceAspect(_ source: NSSize) {
        guard let window else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxSize = NSSize(width: visible.width * 0.72, height: visible.height * 0.72)
        let layoutSource: NSSize
        if let canvas = canvasPreset.aspectSize {
            layoutSource = canvas
        } else {
            switch orientationMode {
            case .portrait:
                layoutSource = source.width <= source.height ? source : NSSize(width: source.height, height: source.width)
            case .landscape:
                layoutSource = source.width >= source.height ? source : NSSize(width: source.height, height: source.width)
            case .automatic, .manual:
                layoutSource = source
            }
        }
        let aspect = layoutSource.width / layoutSource.height
        var content = NSSize(width: maxSize.width, height: maxSize.width / aspect)
        if content.height > maxSize.height {
            content.height = maxSize.height
            content.width = maxSize.height * aspect
        }
        content.width = max(content.width, 320)
        content.height = max(content.height, 180)

        let oldFrame = window.frame
        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        let origin = NSPoint(x: oldFrame.minX, y: oldFrame.maxY - newFrame.height)
        window.setFrame(NSRect(origin: origin, size: newFrame.size), display: true, animate: true)
    }
}
