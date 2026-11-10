// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PosturePal",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PosturePal", targets: ["PosturePal"])],
    targets: [
        .target(name: "PostureCore"),
        .target(name: "MediaPipeBridge"),
        .target(name: "PostureVision", dependencies: ["PostureCore", "MediaPipeBridge"]),
        .executableTarget(name: "PostureProbe", dependencies: ["PostureVision"]),
        .executableTarget(name: "PosturePal", dependencies: ["PostureCore", "PostureVision"]),
        .testTarget(name: "PostureCoreTests", dependencies: ["PostureCore"]),
        .testTarget(name: "PostureVisionTests", dependencies: ["PostureVision"])
    ],
    swiftLanguageModes: [.v5]
)
