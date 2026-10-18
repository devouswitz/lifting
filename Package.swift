// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lifting",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LiftingCore", targets: ["LiftingCore"]), .executable(name: "Lifting", targets: ["LiftingApp"])],
    targets: [
        .target(name: "LiftingCore"),
        .executableTarget(name: "LiftingApp", dependencies: ["LiftingCore"]),
        .testTarget(name: "LiftingCoreTests", dependencies: ["LiftingCore"])
    ],
    swiftLanguageModes: [.v5]
)
