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
        .target(
            name: "whisper",
            path: "Vendor/whisper",
            exclude: [
                "ggml-metal.m",
                "ggml-metal.metal",
                "coreml/whisper-decoder-impl.h",
                "coreml/whisper-decoder-impl.m",
            ],
            sources: [
                "ggml.c",
                "ggml-alloc.c",
                "ggml-backend.c",
                "ggml-quants.c",
                "coreml/whisper-encoder-impl.m",
                "coreml/whisper-encoder.mm",
                "whisper.cpp",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-Wno-shorten-64-to-32"]),
                .define("GGML_USE_ACCELERATE"),
                .define("WHISPER_COREML_ALLOW_FALLBACK"),
                .define("WHISPER_USE_COREML"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreML"),
            ]
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
