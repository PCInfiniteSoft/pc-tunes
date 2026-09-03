// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PCTunes",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PCTunesCore",
            path: "Sources/PCTunesCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PCTunes",
            dependencies: ["PCTunesCore"],
            path: "Sources/PCTunes",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PCTunesTests",
            dependencies: ["PCTunesCore"],
            path: "Sources/PCTunesTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
