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
        .executable(
            name: "CastSprintProbe",
            targets: ["CastSprintProbe"]
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
            name: "CastSprintProbe",
            path: "Sources/CastSprintProbe"
        ),
        .executableTarget(
            name: "CastSprintMac",
            dependencies: ["CCastSprintProtocol"],
            path: "Sources/CastSprintMac",
            exclude: ["Rendering/Shaders.metal"],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        .testTarget(
            name: "CastSprintMacTests",
            dependencies: ["CCastSprintProtocol", "CastSprintMac"],
            path: "Tests/CastSprintMacTests"
        )

    ],
    cxxLanguageStandard: .cxx20
)
