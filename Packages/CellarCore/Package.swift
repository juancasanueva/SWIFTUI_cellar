// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CellarCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "BrewProcess", targets: ["BrewProcess"])
    ],
    targets: [
        .target(
            name: "BrewProcess",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BrewProcessTests",
            dependencies: ["BrewProcess"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
