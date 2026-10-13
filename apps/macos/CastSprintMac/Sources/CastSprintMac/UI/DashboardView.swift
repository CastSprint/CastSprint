// DashboardView.swift — CastSprint Native macOS Gaming Mirroring UI
import SwiftUI
import MetalKit

public struct DashboardView: View {
    @ObservedObject var coordinator = MirroringCoordinator.shared
    @State private var activeTab: AppTab = .home
    @State private var isFullscreen: Bool = false

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
                Text("MAC USB")
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
                    Text("CONNECTED USB DEVICES")
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
                        Text("No iPhone or iPad detected")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(white: 0.5))
                        Text("Connect your device with a data USB cable and unlock the screen.")
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
                        Text("Selected: \(selected.name)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text("Model: \(selected.model)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.6))
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
                            Text(coordinator.isMirroring ? "STOP MIRRORING" : "START MIRRORING")
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

                // Zero-App Guidance Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        Text("NO MOBILE APP REQUIRED")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("1. Connect your iPhone via USB-C or Lightning.\n2. Unlock your iPhone screen.\n3. Tap 'Trust This Computer' and enter passcode.\n4. Click Start Mirroring to view gameplay with <15ms latency!")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)

                Spacer()
            }
            .frame(width: 320)
        }
        .padding(20)
    }

    private func deviceRow(_ device: DiscoveredUSBDevice) -> some View {
        let isSelected = coordinator.selectedDevice?.id == device.id
        return Button(action: { coordinator.selectedDevice = device }) {
            HStack(spacing: 12) {
                Image(systemName: device.isTrueScreenCapture ? "iphone" : "camera.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? Color(red: 0.0, green: 0.9, blue: 1.0) : Color(white: 0.6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isSelected ? .white : Color(white: 0.8))
                    Text(device.isTrueScreenCapture ? "Direct Screen Capture" : "Continuity Camera")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.5))
                }

                Spacer()

                Text(device.state.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .foregroundColor(device.state == .ready ? .green : .orange)
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
                Text("SETTINGS & QUALITY PROFILES")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

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
