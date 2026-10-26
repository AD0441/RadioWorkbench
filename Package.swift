// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RadioWorkbench",
    defaultLocalization: "es",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RadioWorkbench", targets: ["RadioWorkbench"]),
        .library(name: "RadioCore", targets: ["RadioCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "AudioRing"),
        .target(name: "SatelliteKit", path: "Vendor/SatelliteKit/Sources/SatelliteKit"),
        .target(name: "RadioCore", dependencies: ["AudioRing", "SatelliteKit"], linkerSettings: [.linkedFramework("Accelerate"), .linkedFramework("AVFoundation")]),
        .executableTarget(name: "RadioWorkbench", dependencies: ["RadioCore", "AudioRing", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.linkedFramework("Network"), .linkedFramework("PDFKit")]),
        .testTarget(name: "RadioCoreTests", dependencies: ["RadioCore", "RadioWorkbench", "AudioRing"], resources: [.copy("Fixtures")])
    ]
)
