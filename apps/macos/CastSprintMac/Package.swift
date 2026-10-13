// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CastSprintMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CastSprintMac",
            targets: ["CastSprintMac"]
        ),
        .library(
            name: "CCastSprintProtocol",
            targets: ["CCastSprintProtocol"]
        )
    ],
    targets: [
        .target(
            name: "CCastSprintProtocol",
            path: "Sources/CCastSprintProtocol",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .executableTarget(
            name: "CastSprintMac",
            dependencies: ["CCastSprintProtocol"],
            path: "Sources/CastSprintMac",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ],
    cxxLanguageStandard: .cxx20
)
