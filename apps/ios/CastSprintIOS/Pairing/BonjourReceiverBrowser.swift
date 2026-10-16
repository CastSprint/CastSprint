// BonjourReceiverBrowser.swift — Local Network Discovery for CastSprint Receivers
import Foundation
import Network
import Combine
import Darwin

public final class BonjourReceiverBrowser: ObservableObject {
    @Published public private(set) var discoveredReceivers: [DiscoveredReceiver] = []
    @Published public private(set) var isSearching: Bool = false

    private var browser: NWBrowser?
    private let browserQueue = DispatchQueue(label: "com.castsprint.ios.bonjour", qos: .utility)
    private var resolvers: [String: BonjourServiceResolver] = [:]

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
        resolvers.values.forEach { $0.stop() }
        resolvers.removeAll()
        isSearching = false
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var activeKeys = Set<String>()

        for result in results {
            guard case .service(let name, let type, let domain, _) = result.endpoint else {
                continue
            }
            let key = "\(name)|\(type)|\(domain)"
            activeKeys.insert(key)

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

            guard resolvers[key] == nil else { continue }
            let resolver = BonjourServiceResolver(name: name, type: type, domain: domain) { [weak self] resolved in
                guard let self, let resolved else { return }
                let receiver = DiscoveredReceiver(
                    name: name,
                    host: resolved.host,
                    port: resolved.port,
                    platform: platform,
                    pin: pin
                )
                DispatchQueue.main.async {
                    var updated = self.discoveredReceivers.filter { $0.name != name }
                    updated.append(receiver)
                    self.discoveredReceivers = updated.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            }
            resolvers[key] = resolver
            resolver.start()
        }

        DispatchQueue.main.async {
            let liveNames = Set(results.compactMap { result -> String? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return name
            })
            self.discoveredReceivers.removeAll { !liveNames.contains($0.name) }
        }

        for key in Array(resolvers.keys) where !activeKeys.contains(key) {
            resolvers.removeValue(forKey: key)?.stop()
        }
    }
}

private final class BonjourServiceResolver: NSObject, NetServiceDelegate {
    private let service: NetService
    private let completion: ((host: String, port: UInt16)?) -> Void
    private var completed = false

    init(name: String, type: String, domain: String, completion: @escaping ((host: String, port: UInt16)?) -> Void) {
        self.service = NetService(domain: domain, type: type, name: name)
        self.completion = completion
        super.init()
        self.service.delegate = self
    }

    func start() {
        service.resolve(withTimeout: 5.0)
    }

    func stop() {
        service.stop()
        finish(nil)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard sender.port > 0, sender.port <= Int(UInt16.max) else {
            finish(nil)
            return
        }
        let hosts = (sender.addresses ?? []).compactMap(Self.numericHost)
        let host = hosts.first(where: { $0.contains(".") }) ?? hosts.first
        finish(host.map { ($0, UInt16(sender.port)) })
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        finish(nil)
    }

    private func finish(_ result: ((host: String, port: UInt16))?) {
        guard !completed else { return }
        completed = true
        service.stop()
        completion(result)
    }

    private static func numericHost(from data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer in
            guard let address = rawBuffer.bindMemory(to: sockaddr.self).baseAddress else { return nil }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                address,
                socklen_t(data.count),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            return status == 0 ? String(cString: host) : nil
        }
    }
}
