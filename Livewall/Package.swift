// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Livewall",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Livewall", targets: ["Livewall"])],
    targets: [
        .target(name: "LivewallCore"),
        .executableTarget(name: "Livewall", dependencies: ["LivewallCore"]),
        .testTarget(
            name: "LivewallCoreTests",
            dependencies: ["LivewallCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
