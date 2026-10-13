// DashboardView.swift — CastSprint Native macOS Gaming Mirroring UI
import SwiftUI
import MetalKit

public struct DashboardView: View {
    @State private var selectedMode: ConnectionMode = .iphoneUsb
    @State private var isMirroring: Bool = false
    @State private var isRecording: Bool = false
    @State private var isFullscreen: Bool = false
    @State private var selectedDeviceId: String = ""
    @State private var discoveredDevices: [ConnectedDevice] = []

    @State private var currentFps: Double = 60.0
    @State private var currentLatencyMs: Double = 14.2
    @State private var currentJitterMs: Double = 0.8
    @State private var droppedFrames: UInt64 = 0

    let capabilities = PlatformCapabilities.current
    let deviceMonitor = USBDeviceMonitor()

    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.09)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Bar
                headerBar

                Divider().background(Color(white: 0.2))

                // Main Content
                HStack(spacing: 0) {
                    // Left Control Sidebar
                    sidebarControls
                        .frame(width: 320)
                        .background(Color(red: 0.07, green: 0.09, blue: 0.12))

                    Divider().background(Color(white: 0.2))

                    // Right Media Surface / Gaming View
                    gamingSurfaceView
                }

                Divider().background(Color(white: 0.2))

                // Bottom Status & Telemetry Bar
                bottomTelemetryBar
            }
        }
        .onAppear {
            deviceMonitor.start()
            deviceMonitor.refreshDevices()
            self.discoveredDevices = deviceMonitor.connectedDevices
            if let first = discoveredDevices.first {
                self.selectedDeviceId = first.id
            }
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                .font(.system(size: 18, weight: .bold))

            Text("CastSprint")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            Text("PRO GAMING MIRROR")
                .font(.system(size: 9, weight: .heavy))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.15))
                .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                .cornerRadius(4)

            Spacer()

            // Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(isMirroring ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(isMirroring ? "ACTIVE STREAM" : "STANDBY")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isMirroring ? .green : .orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.4))
            .cornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.04, green: 0.05, blue: 0.07))
    }

    // MARK: - Sidebar Controls
    private var sidebarControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Mode Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("CONNECTION MODE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.6))

                ForEach(ConnectionMode.allCases) { mode in
                    let isSupported = capabilities.isModeSupported(mode)
                    Button(action: {
                        if isSupported {
                            selectedMode = mode
                        }
                    }) {
                        HStack {
                            Image(systemName: iconForMode(mode))
                                .frame(width: 20)
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            if !isSupported {
                                Text("NOT SUPPORTED")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.15))
                                    .cornerRadius(3)
                            } else if !mode.requiresCompanionApp {
                                Text("NO APP")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.15))
                                    .cornerRadius(3)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedMode == mode ? Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.15) : Color.white.opacity(0.04))
                        .foregroundColor(selectedMode == mode ? Color(red: 0.0, green: 0.9, blue: 1.0) : (isSupported ? .white : Color(white: 0.4)))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSupported)
                }
            }

            // Quick Guidance Note
            guidanceCard

            Spacer()

            // Stream Action Controls
            VStack(spacing: 10) {
                Button(action: {
                    isMirroring.toggle()
                }) {
                    HStack {
                        Image(systemName: isMirroring ? "stop.fill" : "play.fill")
                        Text(isMirroring ? "STOP MIRRORING" : "START MIRRORING")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isMirroring ? Color.red : Color(red: 0.0, green: 0.8, blue: 0.95))
                    .foregroundColor(isMirroring ? .white : .black)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Button(action: {
                        isRecording.toggle()
                    }) {
                        HStack {
                            Circle().fill(isRecording ? Color.red : Color.white).frame(width: 8, height: 8)
                            Text(isRecording ? "RECORDING" : "REC [R]")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isRecording ? Color.red.opacity(0.2) : Color.white.opacity(0.08))
                        .foregroundColor(isRecording ? .red : .white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        isFullscreen.toggle()
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                            Text("FULL [F11]")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                Text(selectedMode == .iphoneUsb ? "ZERO-APP IPHONE MIRRORING" : "CONNECTION GUIDE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            if selectedMode == .iphoneUsb {
                Text("1. Connect iPhone with USB cable.\n2. Tap 'Trust This Computer' on phone.\n3. Click Start Mirroring. No mobile app required!")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.7))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Launch CastSprint on your mobile device and connect to the same Wi-Fi network.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.7))
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.3))
        .cornerRadius(6)
    }

    // MARK: - Gaming Surface
    private var gamingSurfaceView: some View {
        ZStack {
            Color.black

            if isMirroring {
                VStack {
                    Text("Direct Metal Gaming Surface Active")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(white: 0.6))
                    Text("OBS Window Capture Source: [CastSprint]: CastSprint — Gaming View")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "display")
                        .font(.system(size: 48))
                        .foregroundColor(Color(white: 0.2))
                    Text("NO ACTIVE STREAM")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(white: 0.4))
                    Text("Select a device and tap Start Mirroring")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.3))
                }
            }
        }
    }

    // MARK: - Bottom Telemetry Bar
    private var bottomTelemetryBar: some View {
        HStack(spacing: 24) {
            statMetric(label: "LATENCY", value: String(format: "%.1f ms", currentLatencyMs), highlight: true)
            statMetric(label: "FPS", value: String(format: "%.1f", currentFps), highlight: false)
            statMetric(label: "JITTER", value: String(format: "%.2f ms", currentJitterMs), highlight: false)
            statMetric(label: "DROPPED", value: "\(droppedFrames)", highlight: false)

            Spacer()

            Text("CastSprint v0.2.0 Beta · Free Forever")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.04, green: 0.05, blue: 0.07))
    }

    private func statMetric(label: String, value: String, highlight: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.5))
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(highlight ? Color(red: 0.0, green: 0.9, blue: 1.0) : .white)
        }
    }

    private func iconForMode(_ mode: ConnectionMode) -> String {
        switch mode {
        case .iphoneUsb: return "cable.connector"
        case .androidUsb: return "cable.connector.horizontal"
        case .iphoneWifi: return "wifi"
        case .androidWifi: return "wifi"
        case .iphoneWindowsUsb: return "exclamationmark.triangle"
        }
    }
}
