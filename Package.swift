// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DeadAir",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "DeadAir",
            path: "Sources/DeadAir",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
