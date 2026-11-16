// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LuminaCore"),
        .executableTarget(
            name: "Lumina",
            dependencies: ["LuminaCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreGraphics")]
        ),
        .testTarget(name: "LuminaCoreTests", dependencies: ["LuminaCore"]),
    ]
)
