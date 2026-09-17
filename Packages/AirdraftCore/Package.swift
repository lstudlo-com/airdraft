// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AirdraftCore",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "AirdraftCore", targets: ["AirdraftCore"]),
        .executable(name: "airdraft-cli", targets: ["airdraft-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // No tagged releases; pinned to the revision the app was verified with.
        .package(url: "https://github.com/soniqo/speech-swift", revision: "d655076badd143f99c9ce19642fbea8b643ccc0b"),
        .package(path: "../SherpaOnnxKit"),
    ],
    targets: [
        .target(
            name: "AirdraftCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "CohereTranscribeASR", package: "speech-swift"),
                .product(name: "SherpaOnnx", package: "SherpaOnnxKit"),
            ]
        ),
        .executableTarget(
            name: "airdraft-cli",
            dependencies: ["AirdraftCore"]
        ),
        .testTarget(
            name: "AirdraftCoreTests",
            dependencies: ["AirdraftCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
