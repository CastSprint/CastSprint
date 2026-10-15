// DashboardView.swift — CastSprint Native macOS Gaming Mirroring UI
import SwiftUI
import MetalKit

public struct DashboardView: View {
    @ObservedObject var coordinator = MirroringCoordinator.shared
    @State private var activeTab: AppTab = .home
    @State private var isFullscreen: Bool = false

    @State private var wirelessAdbHost: String = ""
    @State private var wirelessAdbPort: String = "5555"
    @State private var wirelessAdbCode: String = ""
    @State private var wirelessAdbStatus: String = ""
    @State private var isBleScanning: Bool = false

    private let bleProvider = OptionalBluetoothDiscoveryProvider()
    private let usbNetProvider = ExperimentalUsbNetworkProvider()
    private let airPlayIntegration = AirPlaySystemIntegration()

    enum AppTab: String, CaseIterable, Identifiable {
        case home = "Home"
        case mirror = "Mirror View"
        case settings = "Settings"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .mirror: return "display"
            case .settings: return "gearshape.fill"
            }
        }
    }

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
                    switch activeTab {
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
                    Button(action: { activeTab = tab }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(activeTab == tab ? Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.15) : Color.clear)
                        .foregroundColor(activeTab == tab ? Color(red: 0.0, green: 0.9, blue: 1.0) : Color(white: 0.7))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Stream State Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(coordinator.isMirroring ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(coordinator.isMirroring ? "STREAMING" : "STANDBY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(coordinator.isMirroring ? .green : .orange)
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
                            activeTab = .mirror
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
        if let selected = coordinator.selectedDevice, selected.isTestDevice {
            return "START PROTOCOL TEST STREAM"
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
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        Text("ZERO MOBILE APP REQUIRED")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("1. Connect iPhone/iPad via USB cable.\n2. Unlock screen & tap 'Trust This Computer'.\n3. Click Start Mirroring for sub-15ms uncompressed display!")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.7))

                case (.android, .usb):
                    HStack {
                        Image(systemName: "bolt.horizontal.fill")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        Text("ANDROID USB (ADB REVERSE)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("1. Enable Developer Options & USB Debugging.\n2. Connect phone via USB cable.\n3. CastSprint auto-configures port 27183 reverse proxy and launches the Android app.")
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
                            Text("LOCAL WI-FI (LAN) PAIRING")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("• Method 1 (CastSprint Mobile App):\n  Connect phone and Mac to the same Wi-Fi, open CastSprint, and connect using PIN: \(coordinator.lanPin).\n\n• Method 2 (Instant AirPlay for iPhone/iPad):\n  Swipe down Control Center on your iPhone -> Tap 'Screen Mirroring' -> Select this Mac.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.7))
                    }
                default:
                    EmptyView()
                }
            } else {
                Text("Select a device from the left list to see connection guidance.")
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

                    Text("\(device.videoCapability) · \(device.audioAvailable ? "Audio: Yes" : "Audio: No")")
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
            // Metal Presentation Surface
            MetalViewRepresentable(renderer: coordinator.videoRenderer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Overlaid HUD & Controls
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

                    Spacer()

                    // Real-Time HUD
                    HStack(spacing: 14) {
                        hudMetric(label: "FPS", value: String(format: "%.1f", coordinator.currentFps))
                        hudMetric(label: "LATENCY", value: String(format: "%.1f ms", coordinator.currentLatencyMs))
                        hudMetric(label: "JITTER", value: String(format: "%.2f ms", coordinator.currentJitterMs))
                        if coordinator.droppedFrames > 0 {
                            hudMetric(label: "DROPPED", value: "\(coordinator.droppedFrames)")
                        }
                        if coordinator.activeSessionId > 0 {
                            hudMetric(label: "SESSION", value: "\(coordinator.activeSessionId)")
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
        }
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
                    Text("In OBS Studio for Mac, add a Window Capture source and select: \"CastSprint — Gaming View\".")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
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
                        TextField("Host IP (e.g. 192.168.1.50)", text: $wirelessAdbHost)
                            .textFieldStyle(.roundedBorder)
                        TextField("Port", text: $wirelessAdbPort)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                        TextField("6-digit Code", text: $wirelessAdbCode)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)

                        Button("Pair") {
                            guard let port = UInt16(wirelessAdbPort) else { return }
                            let res = coordinator.adbManager.pairWirelessDevice(host: wirelessAdbHost, port: port, code: wirelessAdbCode)
                            wirelessAdbStatus = res.message
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Connect") {
                            guard let port = UInt16(wirelessAdbPort) else { return }
                            let res = coordinator.adbManager.connectWirelessDevice(host: wirelessAdbHost, port: port)
                            wirelessAdbStatus = res.message
                        }
                        .buttonStyle(.bordered)
                    }

                    if !wirelessAdbStatus.isEmpty {
                        Text(wirelessAdbStatus)
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
                            get: { isBleScanning },
                            set: { val in
                                isBleScanning = val
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

