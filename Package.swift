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
        .binaryTarget(
            name: "whisper",
            path: "Vendor/whisper-v1.8.6/whisper.xcframework"
        ),
        .executableTarget(
            name: "WhisperForMac",
            dependencies: ["whisper"],
            exclude: [
                "Resources/AppIcons",
            ]
        ),
        .testTarget(
            name: "WhisperForMacTests",
            dependencies: ["WhisperForMac"]
        ),
    ]
)
