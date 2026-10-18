// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RadioWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RadioWorkbench", targets: ["RadioWorkbench"]),
        .library(name: "RadioCore", targets: ["RadioCore"])
    ],
    targets: [
        .target(name: "AudioRing"),
        .target(name: "SatelliteKit", path: "Vendor/SatelliteKit/Sources/SatelliteKit"),
        .target(name: "RadioCore", dependencies: ["AudioRing", "SatelliteKit"], linkerSettings: [.linkedFramework("Accelerate"), .linkedFramework("AVFoundation")]),
        .executableTarget(name: "RadioWorkbench", dependencies: ["RadioCore", "AudioRing"], linkerSettings: [.linkedFramework("Network"), .linkedFramework("PDFKit")]),
        .testTarget(name: "RadioCoreTests", dependencies: ["RadioCore", "RadioWorkbench", "AudioRing"], resources: [.copy("Fixtures")])
    ]
)
