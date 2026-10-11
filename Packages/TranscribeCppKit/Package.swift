// swift-tools-version:5.10
import PackageDescription

// Official transcribe.cpp v0.2.4 macOS distribution. Metal is embedded in the
// arm64 slice; Intel uses CPU. No model downloads or unpinned source builds.
let package = Package(
    name: "TranscribeCppKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "TranscribeCppKit", targets: ["TranscribeCppKit"])],
    targets: [
        .binaryTarget(name: "CTranscribe",
                      url: "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.2.4/TranscribeCpp.xcframework.zip",
                      checksum: "243e96ea569583245c9732de3955111210d986c03a34b81424dacde169f9de6a"),
        .target(name: "TranscribeCppKit", dependencies: ["CTranscribe"], linkerSettings: [
            .linkedLibrary("c++"), .linkedLibrary("z"),
            .linkedFramework("Accelerate"), .linkedFramework("Foundation"),
            .linkedFramework("Metal"), .linkedFramework("MetalKit"),
        ]),
    ]
)
