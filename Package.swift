// swift-tools-version: 6.0
// Builds the app executable with SwiftPM (works with just the Command Line Tools).
// `make app` wraps it into AmbientPets.app. No Xcode needed.
import PackageDescription

let package = Package(
    name: "AmbientPets",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "Packages/PetKit")],
    targets: [
        .executableTarget(
            name: "AmbientPets",
            dependencies: [
                .product(name: "PetCore", package: "PetKit"),
                .product(name: "PetPlatform", package: "PetKit"),
            ],
            path: "App",
            exclude: ["Info.plist", "AmbientPets.entitlements"]
        ),
    ]
)
