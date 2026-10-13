// IOSDashboardView.swift — CastSprint iOS Gaming Streaming UI
import SwiftUI
import ReplayKit

public struct IOSDashboardView: View {
    @State private var receiverIP: String = "192.168.1."
    @State private var pairingPin: String = ""
    @State private var selectedPreset: String = "Balanced (1080p 60fps)"
    @State private var isConnected: Bool = false

    let presets = [
        "Low Latency (720p 60fps)",
        "Balanced (1080p 60fps)",
        "High Quality (Native 60fps)"
    ]

    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.09)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Branding Header
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                            .font(.system(size: 24, weight: .bold))
                        Text("CastSprint")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("LOW-LATENCY MOBILE GAMING STREAM")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.15))
                        .cornerRadius(4)
                }
                .padding(.top, 20)

                // Mac USB Pro-Tip Banner
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "laptopcomputer")
                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                        Text("STREAMING TO A MAC?")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Connect via Lightning / USB-C to your Mac for driverless, zero-latency mirroring. No app needed on iPhone!")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.7))
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.3), lineWidth: 1)
                )

                // Connection Setup Card
                VStack(alignment: .leading, spacing: 14) {
                    Text("WI-FI RECEIVER PAIRING")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.6))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Receiver IP (PC or Mac)").font(.system(size: 11)).foregroundColor(Color(white: 0.6))
                        TextField("e.g. 192.168.1.100", text: $receiverIP)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color.black.opacity(0.4))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pairing PIN").font(.system(size: 11)).foregroundColor(Color(white: 0.6))
                        TextField("4-digit PIN", text: $pairingPin)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color.black.opacity(0.4))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }

                    // Preset Selector
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gaming Preset").font(.system(size: 11)).foregroundColor(Color(white: 0.6))
                        Picker("Preset", selection: $selectedPreset) {
                            ForEach(presets, id: \.self) { preset in
                                Text(preset).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(16)
                .background(Color(red: 0.07, green: 0.09, blue: 0.12))
                .cornerRadius(10)

                Spacer()

                // System Broadcast Picker Launcher
                BroadcastPickerView()
                    .frame(height: 52)
                    .background(Color(red: 0.0, green: 0.8, blue: 0.95))
                    .cornerRadius(8)
                    .padding(.horizontal)

                Text("CastSprint is 100% Free · No Ads · No Cloud")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
        }
    }
}

// System Broadcast Picker Wrapper
struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
        picker.preferredExtension = "com.castsprint.ios.broadcast"
        picker.showsMicrophoneButton = true
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
