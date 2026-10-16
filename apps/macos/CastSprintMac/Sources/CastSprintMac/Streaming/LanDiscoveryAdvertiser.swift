// LanDiscoveryAdvertiser.swift — mDNS Bonjour Local Network Advertiser for CastSprint
import Foundation

public final class LanDiscoveryAdvertiser: NSObject, NetServiceDelegate {
    public static let shared = LanDiscoveryAdvertiser()

    private var netService: NetService?
    public private(set) var isAdvertising: Bool = false
    public private(set) var currentPin: String = "000000"

    public override init() {
        super.init()
        generateNewPin()
    }

    public func generateNewPin() {
        let pin = String(format: "%06d", Int.random(in: 0...999_999))
        self.currentPin = pin
    }

    public func startAdvertising(port: Int32 = 27183) {
        stopAdvertising()

        let service = NetService(
            domain: "local.",
            type: "_castsprint._tcp.",
            name: "CastSprint Mac (\(Host.current().localizedName ?? "Mac"))",
            port: port
        )
        service.delegate = self

        // TXT Record
        let txtDict: [String: Data] = [
            "version": "1.0".data(using: .utf8)!,
            "platform": "macOS".data(using: .utf8)!
        ]
        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))

        service.publish()
        self.netService = service
        self.isAdvertising = true
        NSLog("CastSprint Bonjour: Advertising _castsprint._tcp on port %d", port)
    }

    public func stopAdvertising() {
        netService?.stop()
        netService = nil
        isAdvertising = false
    }

    // MARK: - NetServiceDelegate
    public func netServiceDidPublish(_ sender: NetService) {
        NSLog("CastSprint Bonjour: Service successfully published: %@", sender.name)
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        NSLog("CastSprint Bonjour: Service failed to publish: %@", errorDict.description)
        isAdvertising = false
    }
}
