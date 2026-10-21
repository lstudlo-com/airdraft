// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AirdraftCore",
    defaultLocalization: "en",
    platforms: [.macOS("15.0")],
    products: [
        // Keep engine dependencies out of the app preview's JIT linking work.
        .library(name: "AirdraftCore", type: .dynamic, targets: ["AirdraftCore"]),
        .executable(name: "airdraft-cli", targets: ["airdraft-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // No tagged releases; pinned to the revision the app was verified with.
        .package(url: "https://github.com/soniqo/speech-swift", revision: "d655076badd143f99c9ce19642fbea8b643ccc0b"),
        .package(path: "../SherpaOnnxKit"),
        .package(path: "../TranscribeCppKit"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .target(
            name: "AirdraftCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "SpeakerKit", package: "WhisperKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "CohereTranscribeASR", package: "speech-swift"),
                .product(name: "SherpaOnnx", package: "SherpaOnnxKit"),
                .product(name: "TranscribeCppKit", package: "TranscribeCppKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            resources: [.process("Resources")]
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
    // Swift 6 language mode: complete data-race checking is an error, not a warning.
    swiftLanguageModes: [.v6]
)
