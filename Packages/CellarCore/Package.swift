// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CellarCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "BrewProcess", targets: ["BrewProcess"]),
        .library(name: "Catalog", targets: ["Catalog"]),
        .library(name: "BrewClient", targets: ["BrewClient"])
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
        ),
        // Deliberately no dependency on `BrewProcess`: catalog acquisition must
        // never need a `brew` binary (catalog-sync CS1).
        .target(
            name: "Catalog",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CatalogTests",
            dependencies: ["Catalog"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The only target that sees both libraries. The edge is one-directional:
        // nothing depends back on it, so `Catalog` stays brew-free (design D1).
        .target(
            name: "BrewClient",
            dependencies: ["BrewProcess", "Catalog"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BrewClientTests",
            dependencies: ["BrewClient"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
