// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "whisper-for-mac",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "WhisperForMac", targets: ["WhisperForMac"]),
    ],
    targets: [
        .executableTarget(
            name: "WhisperForMac",
            resources: [
                .copy("Resources"),
            ]
        ),
        .testTarget(
            name: "WhisperForMacTests",
            dependencies: ["WhisperForMac"]
        ),
    ]
)
