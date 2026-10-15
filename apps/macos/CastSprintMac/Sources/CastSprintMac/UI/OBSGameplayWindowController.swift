// OBSGameplayWindowController.swift — Dedicated Clean Feed Window for OBS Studio Capture
// CastSprint Multimedia Engineering
import AppKit

@MainActor
public final class OBSGameplayWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = OBSGameplayWindowController()

    private var displayView: MirrorNativeDisplayView?

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 450, height: 975),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CastSprint — Gameplay"
        window.identifier = NSUserInterfaceItemIdentifier("CastSprintGameplayWindow")
        window.minSize = NSSize(width: 320, height: 480)
        window.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)

        super.init(window: window)
        window.delegate = self

        let renderer = MirroringCoordinator.shared.videoRenderer
        let view = MirrorNativeDisplayView(renderer: renderer)
        self.displayView = view
        window.contentView = view

    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func toggleWindow() {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    public func windowWillClose(_ notification: Notification) {
        // Window ordered out, keep reference
    }
}
