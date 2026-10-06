// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "UnityLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "UnityLauncher"),
        .testTarget(
            name: "UnityLauncherTests",
            dependencies: ["UnityLauncher"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
