// swift-tools-version:5.10
import PackageDescription

// Thin package around the repackaged sherpa-onnx static libraries.
// Run scripts/make-sherpa-xcframeworks.sh once to create Vendor/.
let package = Package(
    name: "SherpaOnnxKit",
    platforms: [.macOS("15.0")],
    products: [
        // Keep native archives out of Xcode Preview's JIT linker.
        .library(name: "SherpaOnnx", type: .dynamic, targets: ["SherpaOnnx"]),
    ],
    targets: [
        .binaryTarget(name: "SherpaOnnxC", path: "Vendor/SherpaOnnxC.xcframework"),
        .binaryTarget(name: "onnxruntime", path: "Vendor/onnxruntime.xcframework"),
        .target(
            name: "SherpaOnnx",
            dependencies: ["SherpaOnnxC", "onnxruntime"],
            linkerSettings: [
                // The Swift shim only re-exports a module. Retain the C API
                // object so the dynamic library exports its entry points.
                .unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_SherpaOnnxCreateOfflineRecognizer"]),
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
