// BonjourReceiverBrowser.swift — Local Network Discovery for CastSprint Receivers
import Foundation
import Network
import Combine

public final class BonjourReceiverBrowser: ObservableObject {
    @Published public private(set) var discoveredReceivers: [DiscoveredReceiver] = []
    @Published public private(set) var isSearching: Bool = false

    private var browser: NWBrowser?
    private let browserQueue = DispatchQueue(label: "com.castsprint.ios.bonjour", qos: .utility)

    public init() {}

    public func startBrowsing() {
        stopBrowsing()

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_castsprint._tcp", domain: "local.")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: descriptor, using: parameters)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            self.handleBrowseResults(results)
        }

        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed(let err):
                    NSLog("CastSprint Bonjour Browser failed: %@", err.localizedDescription)
                    self?.isSearching = false
                case .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser.start(queue: browserQueue)
        isSearching = true
    }

    public func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var receivers: [DiscoveredReceiver] = []

        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else {
                continue
            }

            var platform = "Desktop"
            var pin: String? = nil

            if case .bonjour(let txtRecord) = result.metadata {
                let dict = txtRecord.dictionary
                if let platData = dict["platform"] {
                    platform = platData
                }
                if let pinData = dict["pin"] {
                    pin = pinData
                }
            }

            // Estimate host from service name or resolve via connection
            let host = "127.0.0.1"
            let port: UInt16 = 27183

            // Check if name has format or use Bonjour service directly
            receivers.append(DiscoveredReceiver(
                name: name,
                host: host,
                port: port,
                platform: platform,
                pin: pin
            ))
        }

        DispatchQueue.main.async {
            self.discoveredReceivers = receivers
        }
    }
}
