// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoltenVRKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MoltenVRKit", targets: ["MoltenVRKit"]),
    ],
    targets: [
        .target(name: "MoltenVRKit"),
        .testTarget(name: "MoltenVRKitTests", dependencies: ["MoltenVRKit"]),
    ]
)
