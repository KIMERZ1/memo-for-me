// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StickyCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "StickyCore", targets: ["StickyCore"])],
    targets: [
        .target(name: "StickyCore"),
        .testTarget(name: "StickyCoreTests", dependencies: ["StickyCore"]),
    ]
)
