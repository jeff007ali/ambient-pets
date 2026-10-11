// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PetKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PetCore", targets: ["PetCore"]),
        .library(name: "PetImaging", targets: ["PetImaging"]),
        .library(name: "PetPlatform", targets: ["PetPlatform"]),
        .executable(name: "petpack", targets: ["petpack"]),
    ],
    targets: [
        // Pure Swift: models, scheduling, selection, geometry. No AppKit.
        .target(name: "PetCore"),
        // CoreGraphics / ImageIO helpers shared by the app and the CLI. No AppKit.
        .target(name: "PetImaging", dependencies: ["PetCore"]),
        // AppKit / QuartzCore glue: windows, rendering, engine.
        .target(name: "PetPlatform", dependencies: ["PetCore", "PetImaging"]),
        .executableTarget(name: "petpack", dependencies: ["PetCore", "PetImaging"]),
        .testTarget(name: "PetCoreTests", dependencies: ["PetCore"]),
        // AppKit-layer integration tests: pack loading, director planning/sizing (no windows are opened).
        .testTarget(name: "PetPlatformTests", dependencies: ["PetPlatform", "PetCore", "PetImaging"]),
    ]
)
