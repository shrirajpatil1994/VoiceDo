// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceDoShared",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VoiceDoShared",
            targets: ["VoiceDoShared"]
        )
    ],
    targets: [
        .target(
            name: "VoiceDoShared",
            path: "Sources/VoiceDoShared",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "VoiceDoSharedTests",
            dependencies: ["VoiceDoShared"],
            path: "Tests/VoiceDoSharedTests"
        )
    ]
)
