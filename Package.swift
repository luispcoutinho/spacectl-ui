// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceliftGUI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SpaceliftGUI", path: "Sources/SpaceliftGUI")
    ]
)
