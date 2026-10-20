// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Squish",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "squish", targets: ["squish"])],
    targets: [
        .target(name: "SquishCore"),
        .executableTarget(name: "squish", dependencies: ["SquishCore"]),
        .testTarget(name: "SquishCoreTests", dependencies: ["SquishCore"]),
    ]
)
