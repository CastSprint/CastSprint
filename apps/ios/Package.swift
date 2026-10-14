// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CastSprintIOS",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CastSprintIOSCore",
            targets: ["CastSprintIOSCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CastSprintIOSCore",
            path: "CastSprintIOS",
            exclude: [
                "App/CastSprintIOSApp.swift",
                "Info.plist",
                "CastSprintIOS.entitlements"
            ]
        ),
        .testTarget(
            name: "CastSprintIOSTests",
            dependencies: ["CastSprintIOSCore"],
            path: "Tests/CastSprintIOSTests"
        )
    ]
)
