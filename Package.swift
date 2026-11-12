// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PerchKit", targets: ["PerchKit"]),
        .library(name: "PerchUI", targets: ["PerchUI"]),
        .executable(name: "perch", targets: ["perch"]),
    ],
    targets: [
        .target(name: "PerchKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "PerchUI", dependencies: ["PerchKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "perch", dependencies: ["PerchKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "PerchKitTests",
            // PerchUI is here for AppModel, so tests can save through the same path the app does.
            dependencies: ["PerchKit", "PerchUI"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            // Runs the real reader page (Apps/Shared/Web) in an offscreen WebKit view. See TESTING.md.
            name: "PerchRenderTests",
            dependencies: ["PerchKit", "PerchUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
