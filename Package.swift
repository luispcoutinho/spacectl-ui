// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "spacectl-ui",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "spacectl-ui", path: "Sources/spacectl-ui")
    ]
)
