// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MViewer",
            path: "Sources/MViewer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
