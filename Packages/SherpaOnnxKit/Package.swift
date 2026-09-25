// swift-tools-version:5.10
import PackageDescription

// Thin package around the repackaged sherpa-onnx static libraries.
// Run scripts/make-sherpa-xcframeworks.sh once to create Vendor/.
let package = Package(
    name: "SherpaOnnxKit",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "SherpaOnnx", targets: ["SherpaOnnx"]),
    ],
    targets: [
        .binaryTarget(name: "SherpaOnnxC", path: "Vendor/SherpaOnnxC.xcframework"),
        .binaryTarget(name: "onnxruntime", path: "Vendor/onnxruntime.xcframework"),
        .target(
            name: "SherpaOnnx",
            dependencies: ["SherpaOnnxC", "onnxruntime"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
