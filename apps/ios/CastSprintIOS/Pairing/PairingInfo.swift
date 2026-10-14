// PairingInfo.swift — CastSprint LAN Pairing & Security Parameters
import Foundation

public struct PairingInfo: Equatable {
    public let host: String
    public let port: UInt16
    public let fingerprintSha256: String
    public let sessionToken: String
    public let receiverName: String

    public init(
        host: String,
        port: UInt16 = 27183,
        fingerprintSha256: String = "",
        sessionToken: String = "",
        receiverName: String = "Desktop Receiver"
    ) {
        self.host = host
        self.port = port
        self.fingerprintSha256 = fingerprintSha256
        self.sessionToken = sessionToken
        self.receiverName = receiverName
    }

    public static func parse(_ input: String) -> PairingInfo? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("castsprint://") {
            guard let components = URLComponents(string: trimmed) else { return nil }
            let queryItems = components.queryItems ?? []

            var host: String?
            var port: UInt16 = 27183
            var fp = ""
            var token = ""
            var name = "Desktop Receiver"

            for item in queryItems {
                switch item.name {
                case "host": host = item.value
                case "port": if let val = item.value, let p = UInt16(val) { port = p }
                case "fp": fp = item.value ?? ""
                case "token": token = item.value ?? ""
                case "name": name = item.value ?? "Desktop Receiver"
                default: break
                }
            }

            guard let validHost = host, !validHost.isEmpty else { return nil }
            return PairingInfo(host: validHost, port: port, fingerprintSha256: fp, sessionToken: token, receiverName: name)
        } else if trimmed.contains(",") {
            // CSV format: "host,port,fingerprint,token,name"
            let parts = trimmed.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { return nil }

            let host = parts[0]
            let port = UInt16(parts[1]) ?? 27183
            let fp = parts.count > 2 ? parts[2] : ""
            let token = parts.count > 3 ? parts[3] : ""
            let name = parts.count > 4 ? parts[4] : "Desktop Receiver"

            return PairingInfo(host: host, port: port, fingerprintSha256: fp, sessionToken: token, receiverName: name)
        }

        return nil
    }

    public func toUriString() -> String {
        var components = URLComponents()
        components.scheme = "castsprint"
        components.host = "connect"
        components.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "fp", value: fingerprintSha256),
            URLQueryItem(name: "token", value: sessionToken),
            URLQueryItem(name: "name", value: receiverName)
        ]
        return components.string ?? ""
    }
}
