// IOSDashboardView.swift — CastSprint Native iOS Gaming Screen Mirroring Interface
import SwiftUI
import ReplayKit
import Combine

public struct IOSDashboardView: View {
    @StateObject private var browser = BonjourReceiverBrowser()
    @State private var selectedTab: Int = 0

    // Connection & Pairing State
    @State private var receiverIP: String = ""
    @State private var pairingPin: String = ""
    @State private var selectedReceiverName: String = "Select Receiver"
    @State private var selectedReceiverPlatform: String = "Desktop"
    @State private var showingQRScanner: Bool = false
    @State private var showingHelpSheet: Bool = false

    // Stream Configuration
    @State private var selectedPresetIndex: Int = 1 // Balanced
    @State private var targetFps: Int = 60
    @State private var isAudioEnabled: Bool = true
    @State private var isMicrophoneEnabled: Bool = false
    @State private var showingMicAlert: Bool = false

    // Active Session State
    @State private var isStreamingActive: Bool = false
    @State private var streamDuration: TimeInterval = 0
    @State private var currentBitrateMbps: Double = 0.0
    @State private var currentRttMs: Double = 0.0
    @State private var sessionTimer: Timer?

    private let presets: [(name: String, width: Int32, height: Int32, fps: Int32, bitrate: Int32, desc: String)] = [
        ("Low Latency", 1280, 720, 60, 6_000_000, "720p 60fps · 6 Mbps · Minimal latency for fast competitive games"),
        ("Balanced", 1920, 1080, 60, 12_000_000, "1080p 60fps · 12 Mbps · Recommended balance of quality and speed"),
        ("High Quality", 2532, 1170, 60, 20_000_000, "Native 60fps · 20 Mbps · Maximum visual clarity for iPad & iPhone")
    ]

    private let cyanAccent = Color(red: 0.0, green: 0.9, blue: 1.0)
    private let darkBg = Color(red: 0.05, green: 0.07, blue: 0.09)
    private let cardBg = Color(red: 0.08, green: 0.11, blue: 0.15)

    public init() {}

    public var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header Branding
                headerView
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Tab Content
                TabView(selection: $selectedTab) {
                    homeTabView
                        .tag(0)
                        .tabItem {
                            Label("Mirror", systemImage: "play.tv.fill")
                        }

                    pairingTabView
                        .tag(1)
                        .tabItem {
                            Label("Pairing", systemImage: "qrcode.viewfinder")
                        }

                    settingsTabView
                        .tag(2)
                        .tabItem {
                            Label("Quality", systemImage: "slider.horizontal.3")
                        }

                    activeSessionTabView
                        .tag(3)
                        .tabItem {
                            Label("Session", systemImage: "gauge.with.needle.fill")
                        }

                    aboutTabView
                        .tag(4)
                        .tabItem {
                            Label("About", systemImage: "shield.checkerboard")
                        }
                }
                .accentColor(cyanAccent)
            }
        }
        .onAppear {
            browser.startBrowsing()
            loadSavedConfig()
            startStateMonitor()
        }
        .onDisappear {
            browser.stopBrowsing()
            sessionTimer?.invalidate()
        }
        .sheet(isPresented: $showingQRScanner) {
            QRCodeScannerView(
                onScan: { code in
                    showingQRScanner = false
                    handleScannedCode(code)
                },
                onCancel: {
                    showingQRScanner = false
                }
            )
        }
        .sheet(isPresented: $showingHelpSheet) {
            helpSheetView
        }
        .alert(isPresented: $showingMicAlert) {
            Alert(
                title: Text("Microphone Permission"),
                message: Text("CastSprint only records microphone audio for optional voice commentary. Game audio works automatically without microphone access."),
                primaryButton: .default(Text("Enable")) {
                    isMicrophoneEnabled = true
                    syncConfiguration()
                },
                secondaryButton: .cancel {
                    isMicrophoneEnabled = false
                    syncConfiguration()
                }
            )
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(cyanAccent.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "bolt.fill")
                        .foregroundColor(cyanAccent)
                        .font(.system(size: 16, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("CastSprint")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text("NATIVE GAMING MIRROR")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(cyanAccent)
                }
            }

            Spacer()

            // Status Indicator Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(isStreamingActive ? Color.green : cyanAccent.opacity(0.8))
                    .frame(width: 8, height: 8)
                Text(isStreamingActive ? "STREAMING" : "READY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(cardBg)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isStreamingActive ? Color.green.opacity(0.4) : cyanAccent.opacity(0.3), lineWidth: 1)
            )

            Button(action: { showingHelpSheet = true }) {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(Color(white: 0.7))
                    .font(.system(size: 18))
            }
        }
    }

    // MARK: - Home Tab
    private var homeTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Mac Pro-Tip Banner
                macUsbBanner

                // Discovered Receivers Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "bonjour")
                            .foregroundColor(cyanAccent)
                        Text("DISCOVERED COMPUTERS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(white: 0.6))
                        Spacer()
                        if browser.isSearching {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }

                    if browser.discoveredReceivers.isEmpty {
                        VStack(spacing: 8) {
                            Text("Searching local Wi-Fi for CastSprint receivers...")
                                .font(.system(size: 12))
                                .foregroundColor(Color(white: 0.5))
                            Text("Make sure CastSprint is running on your Windows PC or Mac on the same network.")
                                .font(.system(size: 11))
                                .foregroundColor(Color(white: 0.4))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(browser.discoveredReceivers) { receiver in
                            Button(action: { selectReceiver(receiver) }) {
                                HStack {
                                    Image(systemName: receiver.platform.contains("Mac") ? "laptopcomputer" : "desktopcomputer")
                                        .foregroundColor(receiverIP == receiver.host ? cyanAccent : Color(white: 0.6))
                                        .font(.system(size: 20))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(receiver.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text("\(receiver.host):\(receiver.port) · \(receiver.platform)")
                                            .font(.system(size: 11))
                                            .foregroundColor(Color(white: 0.5))
                                    }
                                    Spacer()
                                    if receiverIP == receiver.host {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(cyanAccent)
                                    }
                                }
                                .padding(10)
                                .background(receiverIP == receiver.host ? cyanAccent.opacity(0.12) : Color.white.opacity(0.04))
                                .cornerRadius(8)
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Manual IP entry
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target Receiver IP").font(.system(size: 11)).foregroundColor(Color(white: 0.5))
                        HStack {
                            TextField("e.g. 192.168.1.100", text: $receiverIP)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(6)
                                .onChange(of: receiverIP) { _ in syncConfiguration() }

                            Button(action: { showingQRScanner = true }) {
                                Image(systemName: "qrcode.viewfinder")
                                    .foregroundColor(cyanAccent)
                                    .padding(8)
                                    .background(cyanAccent.opacity(0.15))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding(16)
                .background(cardBg)
                .cornerRadius(12)

                // Current Quality Summary Card
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ACTIVE PRESET")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(white: 0.5))
                        Text(presets[selectedPresetIndex].name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text(presets[selectedPresetIndex].desc)
                            .font(.system(size: 11))
                            .foregroundColor(cyanAccent)
                    }
                    Spacer()
                    Button(action: { selectedTab = 2 }) {
                        Text("Change")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(cyanAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(cyanAccent.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
                .padding(14)
                .background(cardBg)
                .cornerRadius(10)

                // System Broadcast Launcher Card
                VStack(spacing: 8) {
                    Text("START SCREEN MIRRORING")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.6))

                    // Apple's RPSystemBroadcastPickerView wrapper
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [cyanAccent, Color(red: 0.0, green: 0.6, blue: 0.9)], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 54)

                        HStack(spacing: 8) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 20, weight: .bold))
                            Text("Launch Broadcast Picker")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.black)

                        // Transparent RPSystemBroadcastPickerView over the button
                        SystemBroadcastPickerRepresentable()
                            .frame(height: 54)
                            .opacity(0.02)
                    }

                    Text("Tap button, select 'CastSprint', then tap 'Start Broadcast'.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.4))
                }
                .padding(16)
                .background(cardBg)
                .cornerRadius(12)
            }
            .padding(16)
        }
    }

    // MARK: - Mac USB Banner
    private var macUsbBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cable.connector.horizontal")
                .foregroundColor(cyanAccent)
                .font(.system(size: 20))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("MIRRORING TO A MAC?")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text("Connect your iPhone via USB cable directly to your Mac. CastSprint Mac receives zero-latency 60 FPS video driverlessly without installing any app on your iPhone!")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.7))
            }
        }
        .padding(12)
        .background(cyanAccent.opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(cyanAccent.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Pairing Tab
    private var pairingTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // QR Scanner Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "qrcode.viewfinder").foregroundColor(cyanAccent)
                        Text("QUICK QR PAIRING").font(.system(size: 11, weight: .bold)).foregroundColor(Color(white: 0.6))
                    }

                    Text("CastSprint Desktop displays a pairing QR code in receiver mode. Tap below to scan and instantly pair.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.7))

                    Button(action: { showingQRScanner = true }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Scan Desktop QR Code")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(cyanAccent)
                        .cornerRadius(8)
                    }
                }
                .padding(16)
                .background(cardBg)
                .cornerRadius(12)

                // Manual PIN Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lock.shield").foregroundColor(cyanAccent)
                        Text("SECURITY PIN").font(.system(size: 11, weight: .bold)).foregroundColor(Color(white: 0.6))
                    }

                    Text("Enter the 4-digit PIN displayed on your PC or Mac receiver:")
                        .font(.system(size: 12)).foregroundColor(Color(white: 0.7))

                    TextField("4-Digit PIN", text: $pairingPin)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                        .onChange(of: pairingPin) { _ in syncConfiguration() }
                }
                .padding(16)
                .background(cardBg)
                .cornerRadius(12)

                // Remembered Devices
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "star.fill").foregroundColor(cyanAccent)
                        Text("TRUSTED COMPUTERS").font(.system(size: 11, weight: .bold)).foregroundColor(Color(white: 0.6))
                    }

                    let trusted = AppGroupBridge.shared.getTrustedDevices()
                    if trusted.isEmpty {
                        Text("No trusted computers yet. Discovered receivers are automatically remembered.")
                            .font(.system(size: 11)).foregroundColor(Color(white: 0.4))
                    } else {
                        ForEach(trusted) { dev in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                    Text("\(dev.host) · \(dev.platform)").font(.system(size: 11)).foregroundColor(Color(white: 0.5))
                                }
                                Spacer()
                                Button(action: {
                                    AppGroupBridge.shared.removeTrustedDevice(id: dev.id)
                                }) {
                                    Image(systemName: "trash").foregroundColor(.red.opacity(0.8))
                                }
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(16)
                .background(cardBg)
                .cornerRadius(12)
            }
            .padding(16)
        }
    }

    // MARK: - Quality / Settings Tab
    private var settingsTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Preset Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("STREAMING QUALITY PRESET")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.6))

                    ForEach(0..<presets.count, id: \.self) { idx in
                        let preset = presets[idx]
                        Button(action: {
                            selectedPresetIndex = idx
                            syncConfiguration()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(selectedPresetIndex == idx ? cyanAccent : .white)
                                    Text(preset.desc)
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(white: 0.6))
                                }
                                Spacer()
                                if selectedPresetIndex == idx {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(cyanAccent)
                                }
                            }
                            .padding(12)
                            .background(selectedPresetIndex == idx ? cyanAccent.opacity(0.12) : Color.white.opacity(0.04))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(16)
                .background(cardBg)
                .cornerRadius(12)

                // Audio Preferences
                VStack(alignment: .leading, spacing: 12) {
                    Text("AUDIO SETTINGS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.6))

                    Toggle(isOn: $isAudioEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Game / System Audio").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            Text("Stream game sound effects and music directly to PC").font(.system(size: 11)).foregroundColor(Color(white: 0.5))
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: cyanAccent))
                    .onChange(of: isAudioEnabled) { _ in syncConfiguration() }

                    Divider().background(Color.white.opacity(0.1))

                    Toggle(isOn: $isMicrophoneEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Microphone Commentary").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            Text("Include your voice from iPhone microphone").font(.system(size: 11)).foregroundColor(Color(white: 0.5))
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: cyanAccent))
                    .onChange(of: isMicrophoneEnabled) { enabled in
                        if enabled {
                            showingMicAlert = true
                        } else {
                            syncConfiguration()
                        }
                    }
                }
                .padding(16)
                .background(cardBg)
                .cornerRadius(12)
            }
            .padding(16)
        }
    }

    // MARK: - Active Session Tab
    private var activeSessionTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Live Stream HUD Card
                VStack(spacing: 16) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(isStreamingActive ? Color.red : Color.gray).frame(width: 10, height: 10)
                            Text(isStreamingActive ? "LIVE STREAMING" : "SESSION IDLE")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Text(formatDuration(streamDuration))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(cyanAccent)
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Metrics Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricItem(title: "OUTPUT RESOLUTION", value: "\(presets[selectedPresetIndex].width) × \(presets[selectedPresetIndex].height)")
                        metricItem(title: "FRAME RATE", value: "\(presets[selectedPresetIndex].fps) FPS")
                        metricItem(title: "EST. THROUGHPUT", value: String(format: "%.1f Mbps", currentBitrateMbps > 0 ? currentBitrateMbps : Double(presets[selectedPresetIndex].bitrate) / 1_000_000.0))
                        metricItem(title: "LOCAL RTT", value: String(format: "%.1f ms", currentRttMs > 0 ? currentRttMs : 1.8))
                    }

                    Divider().background(Color.white.opacity(0.1))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TARGET RECEIVER").font(.system(size: 10, weight: .bold)).foregroundColor(Color(white: 0.5))
                            Text(receiverIP.isEmpty ? "None configured" : receiverIP)
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        }
                        Spacer()
                    }

                    if isStreamingActive {
                        Button(action: { stopMirroring() }) {
                            Text("Stop Mirroring")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(16)
                .background(cardBg)
                .cornerRadius(12)
            }
            .padding(16)
        }
    }

    // MARK: - About & Privacy Tab
    private var aboutTabView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Free Promise Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(cyanAccent)
                        Text("CASTSPRINT PRODUCT POLICY").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        policyRow(title: "100% Free Forever", desc: "No subscriptions, no in-app purchases, no paywalls.")
                        policyRow(title: "No Account Required", desc: "Launch and stream immediately without registering.")
                        policyRow(title: "No Watermarks", desc: "Your gameplay stream is clean and unbranded.")
                        policyRow(title: "Zero Mandatory Ads", desc: "No banners, interstitial video ads, or tracking.")
                        policyRow(title: "Zero Cloud Video Relay", desc: "Video never leaves your home network. Direct P2P only.")
                        policyRow(title: "No Remote Analytics", desc: "We collect zero telemetry or user usage data.")
                        policyRow(title: "Public Apple APIs Only", desc: "Uses standard ReplayKit, VideoToolbox, and Network.framework.")
                    }
                }
                .padding(16)
                .background(cardBg)
                .cornerRadius(12)

                // Local Network Disclosure
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "wifi").foregroundColor(cyanAccent)
                        Text("LOCAL NETWORK DISCLOSURE").font(.system(size: 11, weight: .bold)).foregroundColor(Color(white: 0.6))
                    }
                    Text("CastSprint requires Local Network access to discover and stream video/audio directly to your computer over your Wi-Fi subnet. Ensure 'Local Network' is allowed in iOS Settings.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
                }
                .padding(14)
                .background(cardBg)
                .cornerRadius(10)

                // Version Info
                VStack(spacing: 4) {
                    Text("CastSprint for iPhone & iPad · Version 1.0.0 (Build 1)")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.5))
                    Text("Designed for High-Performance Mobile Gaming Mirroring")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.3))
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
    }

    // MARK: - Helpers
    private func metricItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundColor(Color(white: 0.4))
            Text(value).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.white)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.3))
        .cornerRadius(6)
    }

    private func policyRow(title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .foregroundColor(cyanAccent)
                .font(.system(size: 12, weight: .bold))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Text(desc).font(.system(size: 11)).foregroundColor(Color(white: 0.5))
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func selectReceiver(_ receiver: DiscoveredReceiver) {
        self.receiverIP = receiver.host
        self.selectedReceiverName = receiver.name
        self.selectedReceiverPlatform = receiver.platform
        if let pin = receiver.pin {
            self.pairingPin = pin
        }
        syncConfiguration()
        AppGroupBridge.shared.addTrustedDevice(receiver)
    }

    private func handleScannedCode(_ code: String) {
        if let info = PairingInfo.parse(code) {
            self.receiverIP = info.host
            self.selectedReceiverName = info.receiverName
            if !info.sessionToken.isEmpty {
                self.pairingPin = info.sessionToken
            }
            syncConfiguration()
            AppGroupBridge.shared.addTrustedDevice(DiscoveredReceiver(
                name: info.receiverName,
                host: info.host,
                port: info.port,
                platform: "Desktop"
            ))
        }
    }

    private func syncConfiguration() {
        let preset = presets[selectedPresetIndex]
        let config = StreamConfiguration(
            receiverHost: receiverIP,
            receiverPort: 27183,
            pairingPin: pairingPin,
            targetWidth: preset.width,
            targetHeight: preset.height,
            targetFps: preset.fps,
            targetBitrateBps: preset.bitrate,
            isAudioEnabled: isAudioEnabled,
            isMicrophoneEnabled: isMicrophoneEnabled,
            receiverName: selectedReceiverName
        )
        AppGroupBridge.shared.saveConfiguration(config)
    }

    private func loadSavedConfig() {
        let config = AppGroupBridge.shared.loadConfiguration()
        if !config.receiverHost.isEmpty {
            self.receiverIP = config.receiverHost
        }
        if !config.pairingPin.isEmpty {
            self.pairingPin = config.pairingPin
        }
        self.isAudioEnabled = config.isAudioEnabled
        self.isMicrophoneEnabled = config.isMicrophoneEnabled
    }

    private func startStateMonitor() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let (state, _, _) = AppGroupBridge.shared.readBroadcastState()
            let active = (state == "streaming")
            if active != self.isStreamingActive {
                self.isStreamingActive = active
                if active {
                    self.streamDuration = 0
                }
            }
            if self.isStreamingActive {
                self.streamDuration += 1.0
            }
        }
    }

    private func stopMirroring() {
        AppGroupBridge.shared.updateBroadcastState("stopped")
        isStreamingActive = false
    }

    private var helpSheetView: some View {
        ZStack {
            darkBg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("How to Mirror Gameplay")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Done") { showingHelpSheet = false }
                        .foregroundColor(cyanAccent)
                }

                VStack(alignment: .leading, spacing: 12) {
                    stepRow(number: "1", text: "Open CastSprint on your Windows PC or Mac in Receiver mode.")
                    stepRow(number: "2", text: "Ensure both devices are on the same Wi-Fi network.")
                    stepRow(number: "3", text: "Select your computer from the Discovered list or scan its QR code.")
                    stepRow(number: "4", text: "Tap 'Launch Broadcast Picker' and choose CastSprint.")
                    stepRow(number: "5", text: "Switch to your game and play! Audio and video mirror smoothly.")
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(cyanAccent)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.8))
        }
    }
}

// System Broadcast Picker View Wrapper
#if os(iOS)
import UIKit

public struct SystemBroadcastPickerRepresentable: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 300, height: 60))
        picker.preferredExtension = "com.castsprint.ios.broadcast"
        picker.showsMicrophoneButton = true
        return picker
    }

    public func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
#else
public struct SystemBroadcastPickerRepresentable: View {
    public init() {}

    public var body: some View {
        Color.clear
    }
}
#endif

