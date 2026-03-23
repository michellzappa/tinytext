// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TinyText",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../Packages/TinyKit"),
    ],
    targets: [
        .executableTarget(
            name: "TinyText",
            dependencies: ["TinyKit"],
            path: "Sources/TinyText",
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
