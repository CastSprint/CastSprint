// CastSprintApp.swift — macOS Application Lifecycle & Main Entry Point
import SwiftUI
import AppKit

@main
struct CastSprintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("CastSprint — Gaming View") {
            DashboardView()
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Automatically activate CoreMediaIO screen capture device provider
        CMIOManager.shared.enableScreenCaptureDevices()
        NSLog("CastSprint: macOS Native Receiver initialized")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
