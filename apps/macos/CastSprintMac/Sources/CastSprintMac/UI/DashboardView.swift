// DashboardView.swift — CastSprint Native macOS Gaming Mirroring UI
import SwiftUI
import MetalKit

public struct DashboardView: View {
    @ObservedObject var coordinator = MirroringCoordinator.shared

    private let bleProvider = OptionalBluetoothDiscoveryProvider.shared
    private let usbNetProvider = ExperimentalUsbNetworkProvider()
    private let airPlayIntegration = AirPlaySystemIntegration()

    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.09)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                topNavigationBar

                Divider().background(Color(white: 0.2))

                // Active View Body
                Group {
                    switch coordinator.activeTab {
                    case .home:
                        homeView
                    case .mirror:
                        mirrorView
                    case .settings:
                        settingsView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().background(Color(white: 0.2))

                // Bottom Status Bar
                bottomStatusBar
            }
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        HStack(spacing: 16) {
            // Brand
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                    .font(.system(size: 16, weight: .bold))
                Text("CastSprint")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text("MAC UNIFIED")
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.15))
                    .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                    .cornerRadius(4)
            }

            Spacer()

            // Tab Selector
            HStack(spacing: 4) {
                ForEach(AppTab.allCases) { tab in
                    Button(action: { coordinator.activeTab = tab }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(coordinator.activeTab == tab ? Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.15) : Color.clear)
                        .foregroundColor(coordinator.activeTab == tab ? Color(red: 0.0, green: 0.9, blue: 1.0) : Color(white: 0.7))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityIdentifier("tab_\(tab.id.lowercased().replacingOccurrences(of: " ", with: "_"))")
                }
            }

            Spacer()

            // Stream State Pill (Truthful State: STANDBY -> WAITING FOR PHONE -> LIVE STREAMING)
            HStack(spacing: 6) {
                Circle()
                    .fill(statusPillColor)
                    .frame(width: 8, height: 8)
                Text(statusPillText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(statusPillColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.4))
            .cornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.04, green: 0.05, blue: 0.07))
    }

    private var statusPillColor: Color {
        switch coordinator.sessionState {
        case .idle: return Color(white: 0.5)
        case .listening, .waitingForVideo, .negotiating: return Color.yellow
        case .pairing, .authenticated, .receivingVideo: return Color.cyan
        case .rendering: return Color.green
        case .error, .disconnected: return Color.red
        }
    }

    private var statusPillText: String {
        switch coordinator.sessionState {
        case .idle: return "AVAILABLE"
        case .listening: return "CONNECTING"
        case .pairing: return "PAIRING..."
        case .authenticated: return "AUTHENTICATED"
        case .negotiating: return "CAPTURE_CONFIGURING"
        case .waitingForVideo: return "WAITING_FOR_DISPLAY_FRAMES"
        case .receivingVideo: return "RECEIVING_FRAMES"
        case .rendering: return "DISPLAY_STREAMING"
        case .disconnected: return "DISCONNECTED"
        case .error: return "ERROR"
        }
    }


    // MARK: - Tab 1: Home View
    private var homeView: some View {
        HStack(spacing: 24) {
            // Left Column: Devices List
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("CONNECTED & DISCOVERED DEVICES")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.6))
                    Spacer()
                    Button(action: { coordinator.refreshDevices() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                    }
                    .buttonStyle(.plain)
                }

                if coordinator.availableDevices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cable.connector")
                            .font(.system(size: 36))
                            .foregroundColor(Color(white: 0.3))
                        Text("Searching for Devices...")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(white: 0.5))
                        Text("Connect your iPhone/Android via USB or connect to the same Wi-Fi network.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.4))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(8)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(coordinator.availableDevices) { device in
                                deviceRow(device)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Right Column: Controls & Guidance
            VStack(alignment: .leading, spacing: 16) {
                // Device Action Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("MIRRORING CONTROLS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.6))

                    if let selected = coordinator.selectedDevice {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selected.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Text("\(selected.platform.rawValue) · \(selected.transport.rawValue) · \(selected.videoCapability)")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(white: 0.6))
                            }
                            Spacer()
                        }
                    } else {
                        Text("Select a device from the list")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.5))
                    }

                    Button(action: {
                        if coordinator.isMirroring {
                            coordinator.stopMirroring()
                        } else {
                            coordinator.startMirroring()
                            coordinator.activeTab = .mirror
                        }
                    }) {
                        HStack {
                            Image(systemName: coordinator.isMirroring ? "stop.fill" : "play.fill")
                            Text(buttonTitle)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(coordinator.isMirroring ? Color.red : Color(red: 0.0, green: 0.8, blue: 0.95))
                        .foregroundColor(coordinator.isMirroring ? .white : .black)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(buttonTitle)
                    .accessibilityIdentifier("btn_toggle_mirroring")
                    .disabled(coordinator.selectedDevice == nil)
                }
                .padding(16)
                .background(Color(red: 0.07, green: 0.09, blue: 0.12))
                .cornerRadius(8)

                // Dynamic Contextual Guidance Card
                guidanceCard

                Spacer()
            }
            .frame(width: 320)
        }
        .padding(20)
    }

    private var buttonTitle: String {
        if coordinator.isMirroring {
            return "STOP MIRRORING"
        }
        if let selected = coordinator.selectedDevice {
            if selected.isTestDevice {
                return "START PROTOCOL TEST STREAM"
            }
            if selected.id.hasPrefix("screen-") {
                return "START SCREEN MIRRORING"
            }
        }
        return "START MIRRORING"
    }

    @ViewBuilder
    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected = coordinator.selectedDevice {
                switch (selected.platform, selected.transport) {
                case (.ios, .usb):
                    HStack {
                        Image(systemName: "iphone.gen3")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        Text("IPHONE USB DISPLAY & SYSTEM AUDIO (OBS READY)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("• Hardware Screen Capture (Zero-Camera):\n  Connect unlocked iPhone 15 via USB-C cable and tap 'Trust This Computer'. CastSprint captures the raw hardware display surface via CoreMediaIO.\n\n• Audio Playback & OBS:\n  The iPhone's internal game audio routes directly through your Mac's speakers and is captured by OBS Studio via Window Capture or macOS Audio Capture.\n\n• Tournament Rule:\n  Physical room microphones and Continuity Cameras are strictly excluded.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.7))

                case (.android, .usb):
                    HStack {
                        Image(systemName: "bolt.horizontal.fill")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        Text("ANDROID USB (APP-LESS SCREENRECORD)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("1. Enable Developer Options & USB Debugging on Android.\n2. Connect phone via USB cable.\n3. Click 'START MIRRORING' to stream 60 FPS hardware H.264 display frames directly via ADB with zero APK installation required.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.7))

                case (_, .wifi):
                    if selected.isTestDevice {
                        HStack {
                            Image(systemName: "testtube.2")
                                .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                            Text("RECEIVER TEST SIMULATOR")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("Streams simulated 60 FPS H.264 video and audio packets over TCP port 27183 to validate the VideoToolbox hardware decompressor and Metal rendering pipeline.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.7))
                    } else {
                        HStack {
                            Image(systemName: "wifi")
                                .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                            Text("DIRECT WI-FI (LAN) STREAMING")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("1. Connect phone and Mac to the same Wi-Fi network.\n2. Open CastSprint iOS or Android companion app.\n3. Enter Pairing PIN: \(coordinator.lanPin) to stream directly to this Mac.\n4. In OBS: Add Window Capture -> 'CastSprint'.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.7))
                    }
                default:
                    EmptyView()
                }
            } else {
                Text("Connect your iPhone via USB-C cable, unlock screen, and tap 'Trust This Computer'.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.5))
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
    }

    private func deviceRow(_ device: UnifiedDevice) -> some View {
        let isSelected = coordinator.selectedDevice?.id == device.id
        return Button(action: { coordinator.selectedDevice = device }) {
            HStack(spacing: 12) {
                Image(systemName: device.systemIcon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? Color(red: 0.0, green: 0.9, blue: 1.0) : Color(white: 0.6))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isSelected ? .white : Color(white: 0.8))

                        // Platform Pill
                        Text(device.platform.rawValue)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(device.platform == .ios ? Color.blue.opacity(0.3) : (device.platform == .universal ? Color.cyan.opacity(0.25) : Color.green.opacity(0.3)))
                            .foregroundColor(device.platform == .ios ? .cyan : (device.platform == .universal ? Color(red: 0.0, green: 0.9, blue: 1.0) : .green))
                            .cornerRadius(3)

                        // Transport Pill
                        Text(device.transport.rawValue)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(device.transport == .usb ? Color.purple.opacity(0.3) : Color.teal.opacity(0.3))
                            .foregroundColor(device.transport == .usb ? .purple : .teal)
                            .cornerRadius(3)
                    }

                    let audioDesc: String = {
                        if device.transport == .usb && device.platform == .ios {
                            return "Audio: Enable in Audio MIDI Setup"
                        } else if device.audioAvailable {
                            return "Audio: System/Game Audio"
                        } else {
                            return "Audio: None"
                        }
                    }()
                    Text("\(device.videoCapability) · \(audioDesc)")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.5))
                }

                Spacer()

                Text(device.status.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .foregroundColor(device.status == .ready ? .green : (device.status == .active ? .cyan : .orange))
                    .cornerRadius(4)
            }
            .padding(12)
            .background(isSelected ? Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.12) : Color.white.opacity(0.03))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 2: Mirror View
    private var mirrorView: some View {
        ZStack {
            // Metal Presentation Surface (Zero-Copy GPU Presentation)
            MetalViewRepresentable(renderer: coordinator.videoRenderer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Explicit State Overlay: Never show a bare black screen without status
            if coordinator.sessionState != .rendering || !coordinator.videoRenderer.hasPresentedFrame {
                sessionWaitingOverlay
            }

            // Overlaid HUD & Controls
            if coordinator.showHud {
                VStack {
                    // Top Overlay Controls
                    HStack(spacing: 12) {
                        Button(action: { coordinator.toggleRecording() }) {
                            HStack(spacing: 6) {
                                Circle().fill(coordinator.isRecording ? Color.red : Color.white).frame(width: 8, height: 8)
                                Text(coordinator.isRecording ? "REC \(formatDuration(coordinator.recordingDuration))" : "RECORD [R]")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(coordinator.isRecording ? Color.red.opacity(0.8) : Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { coordinator.toggleMute() }) {
                            Image(systemName: coordinator.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(coordinator.isMuted ? .red : .white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { coordinator.takeScreenshot() }) {
                            Image(systemName: "camera.fill")
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            OBSGameplayWindowController.shared.toggleWindow()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "pip.enter")
                                Text("OBS CLEAN WINDOW")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.2))
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Section("Orientation") {
                                ForEach(CreatorOrientationMode.allCases, id: \.rawValue) { mode in
                                    Button(mode.rawValue) {
                                        OBSGameplayWindowController.shared.setOrientationMode(mode)
                                    }
                                }
                            }
                            Section("Output Canvas") {
                                ForEach(CreatorCanvasPreset.allCases, id: \.rawValue) { preset in
                                    Button(preset.rawValue) {
                                        OBSGameplayWindowController.shared.setCanvasPreset(preset)
                                    }
                                }
                            }
                        } label: {
                            Label("OUTPUT", systemImage: "rectangle.on.rectangle")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 78)

                        Spacer()

                        // Real-Time Truthful HUD: Independent Capture & Render Telemetry
                        HStack(spacing: 12) {
                            hudMetric(label: "CAPTURE", value: coordinator.isMirroring ? String(format: "%.1f FPS", coordinator.captureFps) : "0.0")
                            hudMetric(label: "PREVIEW", value: (coordinator.sessionState == .rendering && coordinator.renderFps > 0) ? String(format: "%.1f FPS", coordinator.renderFps) : "0.0")
                            if coordinator.gameplayWindowFps > 0 {
                                hudMetric(label: "OBS", value: String(format: "%.1f FPS", coordinator.gameplayWindowFps))
                            }
                            if !coordinator.capturePixelFormat.isEmpty && coordinator.capturePixelFormat != "None" {
                                hudMetric(label: "FORMAT", value: "\(coordinator.capturePixelFormat) \(coordinator.captureResolution)")
                            }
                            hudMetric(label: "AUDIO", value: coordinator.sessionState == .rendering ? (coordinator.audioOutput.hasReceivedAudio ? "ACTIVE (48 kHz)" : "MUXED USB / LAN") : "STANDBY")
                            if coordinator.droppedFrames > 0 {
                                hudMetric(label: "DROPPED", value: "\(coordinator.droppedFrames)")
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                    }
                    .padding(12)

                    Spacer()
                }
            } else {
                // Subtle restore overlay button in bottom-right corner
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { coordinator.showHud = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                Text("SHOW HUD")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.5))
                            .foregroundColor(.white.opacity(0.8))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sessionWaitingOverlay: some View {
        VStack(spacing: 16) {
            switch coordinator.sessionState {
            case .idle:
                Image(systemName: "display")
                    .font(.system(size: 44))
                    .foregroundColor(Color(white: 0.3))
                Text("Standby")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(white: 0.6))
                Text("Select a device in Home and click Start Mirroring.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.4))

            case .listening:
                Image(systemName: "wifi")
                    .font(.system(size: 44))
                    .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                Text("WAITING FOR PHONE CONNECTION")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                VStack(spacing: 4) {
                    Text("PAIRING PIN")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(white: 0.6))
                    Text(coordinator.lanPin)
                        .font(.system(size: 32, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                }

                Text("1. Connect iPhone or Android to the same local Wi-Fi.\n2. Open CastSprint app on your phone.\n3. Enter PIN \(coordinator.lanPin) and tap Start Mirroring.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.7))
                    .multilineTextAlignment(.center)

            case .pairing, .authenticated:
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.cyan))
                Text("AUTHENTICATING DEVICE...")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(coordinator.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.7))

            case .negotiating, .waitingForVideo, .receivingVideo:
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.yellow))
                Text("WAITING FOR VIDEO STREAM...")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(coordinator.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.7))

            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.red)
                Text("MIRRORING ERROR")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
                Text(coordinator.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

            case .disconnected:
                Image(systemName: "cable.connector.slash")
                    .font(.system(size: 44))
                    .foregroundColor(.orange)
                Text("DEVICE DISCONNECTED")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.orange)
                Text("The mirroring session was terminated.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.5))

            case .rendering:
                EmptyView()
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }


    private func hudMetric(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color(white: 0.6))
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
        }
    }

    // MARK: - Tab 3: Settings View
    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("SETTINGS & CONFIGURATION")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                // Wi-Fi Pairing
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wi-Fi (LAN) Pairing PIN").font(.system(size: 12, weight: .bold)).foregroundColor(Color(white: 0.7))
                    HStack(spacing: 12) {
                        Text(coordinator.lanPin)
                            .font(.system(size: 20, weight: .heavy, design: .monospaced))
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(6)

                        Button("Generate New PIN") {
                            coordinator.lanAdvertiser.generateNewPin()
                            coordinator.lanPin = coordinator.lanAdvertiser.currentPin
                            coordinator.lanAdvertiser.startAdvertising(port: 27183)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    Text("Enter this PIN on your Android or iOS device when pairing over the local network.")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.5))
                }

                // ADB Status
                VStack(alignment: .leading, spacing: 8) {
                    Text("Android ADB Tool Path").font(.system(size: 12, weight: .bold)).foregroundColor(Color(white: 0.7))
                    Text(coordinator.adbManager.adbPath ?? "Not Detected (Run: brew install android-platform-tools)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(coordinator.adbManager.adbPath != nil ? Color.green : Color.orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Capture Quality Profile").font(.system(size: 12, weight: .bold)).foregroundColor(Color(white: 0.7))
                    Picker("Profile", selection: $coordinator.qualityProfile) {
                        ForEach(CaptureQualityProfile.allCases) { profile in
                            Text(profile.rawValue).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Capture iPhone internal audio", isOn: $coordinator.capturePhoneAudio)
                        .font(.system(size: 12, weight: .bold))
                    Text("Optional. macOS classifies the selected USB device audio input under Microphone privacy. Video-only mirroring never requests this permission.")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.6))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Volume: \(Int(coordinator.audioVolume * 100))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.7))
                    Slider(value: Binding(get: { coordinator.audioVolume }, set: { coordinator.setVolume($0) }), in: 0...1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording Destination").font(.system(size: 12, weight: .bold)).foregroundColor(Color(white: 0.7))
                    Text("~/Movies/CastSprint (Zero-transcode MP4)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("OBS Studio Window Capture Hook").font(.system(size: 12, weight: .bold)).foregroundColor(Color(white: 0.7))
                    Text("In OBS Studio for Mac, add a Window Capture source and select: \"CastSprint — Gameplay\".")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("One-frame Source Diagnostic")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.7))
                    Text("With the iPhone Home Screen visible, explicitly capture the next source frame as one PNG plus metadata. CastSprint never saves diagnostic frames continuously.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
                    Button("Capture Next Source Frame") {
                        coordinator.captureOneDiagnosticSourceFrame()
                    }
                    .disabled(!coordinator.isMirroring)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Capture one diagnostic source frame")
                }

                Divider().background(Color(white: 0.2))

                // Wireless ADB Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        Text("WIRELESS ADB PAIRING & CONNECT (ANDROID 11+)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("On Android: Settings -> Developer Options -> Wireless Debugging -> Pair device with pairing code.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))

                    HStack(spacing: 8) {
                        TextField("Host IP (e.g. 192.168.1.50)", text: $coordinator.wirelessAdbHost)
                            .textFieldStyle(.roundedBorder)
                        TextField("Port", text: $coordinator.wirelessAdbPort)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                        TextField("6-digit Code", text: $coordinator.wirelessAdbCode)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)

                        Button("Pair") {
                            guard let port = UInt16(coordinator.wirelessAdbPort) else { return }
                            coordinator.isWirelessAdbBusy = true
                            coordinator.wirelessAdbStatus = "Pairing…"
                            coordinator.adbManager.pairWirelessDevice(host: coordinator.wirelessAdbHost, port: port, code: coordinator.wirelessAdbCode) { result in
                                coordinator.wirelessAdbStatus = result.message
                                coordinator.isWirelessAdbBusy = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(coordinator.isWirelessAdbBusy)

                        Button("Connect") {
                            guard let port = UInt16(coordinator.wirelessAdbPort) else { return }
                            coordinator.isWirelessAdbBusy = true
                            coordinator.wirelessAdbStatus = "Connecting…"
                            coordinator.adbManager.connectWirelessDevice(host: coordinator.wirelessAdbHost, port: port) { result in
                                coordinator.wirelessAdbStatus = result.message
                                coordinator.isWirelessAdbBusy = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(coordinator.isWirelessAdbBusy)
                    }

                    if !coordinator.wirelessAdbStatus.isEmpty {
                        Text(coordinator.wirelessAdbStatus)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                    }
                }
                .padding(14)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)

                // Apple AirPlay Mode Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "airplayvideo")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        Text("APPLE AIRPLAY (SYSTEM MODE)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("macOS includes a native AirPlay Receiver. When enabled, iPhone users can mirror their screen via Control Center with zero companion app.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))

                    Button("Open macOS AirPlay Receiver Settings") {
                        airPlayIntegration.openSystemAirPlaySettings()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)

                // USB Network Tethering Diagnostics
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        Text("USB NETWORK TETHERING (CDC-NCM)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    let ifaces = usbNetProvider.detectUsbNetworkInterfaces()
                    if ifaces.isEmpty {
                        Text("No active USB Ethernet tethering interfaces detected. Turn on USB Tethering in phone settings.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.5))
                    } else {
                        ForEach(ifaces, id: \.name) { iface in
                            Text("Active: \(iface.name) · IP: \(iface.ip)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color.green)
                        }
                    }
                }
                .padding(14)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)

                // Bluetooth Discovery Assistant
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "wave.3.left")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        Text("BLUETOOTH DISCOVERY ASSISTANT")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { coordinator.isBleScanning },
                            set: { val in
                                coordinator.isBleScanning = val
                                if val { bleProvider.startScanning() } else { bleProvider.stopScanning() }
                            }
                        ))
                        .labelsHidden()
                    }
                    Text("Optional BLE beacon scanning to exchange Wi-Fi IP and PIN automatically. Streaming is always routed over USB or Wi-Fi.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
                }
                .padding(14)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
            }
            .padding(24)
        }
    }

    // MARK: - Bottom Status Bar
    private var bottomStatusBar: some View {
        HStack {
            Text(coordinator.statusMessage)
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.5))
            Spacer()
            Text("CastSprint for Mac · 100% Free Forever")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(red: 0.04, green: 0.05, blue: 0.07))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

