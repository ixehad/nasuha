// swift-tools-version:5.10
import PackageDescription

// NasuhaCore holds everything that doesn't need UIKit: the content reader,
// the topic catalog, the SwiftData models and the colour tokens.
// It builds for macOS too, so `swift test` runs without a simulator.
let package = Package(
    name: "NasuhaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NasuhaCore", targets: ["NasuhaCore"]),
    ],
    dependencies: [
        // GRDB.swift (MIT) is the only third-party package.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "NasuhaCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "NasuhaCoreTests",
            dependencies: ["NasuhaCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
