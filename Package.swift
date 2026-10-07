// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Whisk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Whisk",
            path: "Sources/Whisk",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
