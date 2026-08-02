// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CellarCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "BrewProcess", targets: ["BrewProcess"]),
        .library(name: "Catalog", targets: ["Catalog"]),
        .library(name: "BrewClient", targets: ["BrewClient"]),
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    targets: [
        // Test-only helpers shared by the three test targets (design D9, M2-0 D5).
        // It declares **no dependencies** — `TestClock` needs only `Synchronization`
        // and `TestPoll` only the stdlib — which is exactly what lets it exist
        // without giving any test target an edge it must not have. It is a
        // `.target` and not a product, so nothing links it into the app.
        .target(
            name: "CellarTestSupport",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "BrewProcess",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BrewProcessTests",
            dependencies: ["BrewProcess", "CellarTestSupport"],
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
            dependencies: ["Catalog", "CellarTestSupport"],
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
            dependencies: ["BrewClient", "CellarTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The outermost node of the graph (design D1): it sees `BrewClient` so the
        // history draft -> row mapping stays testable in CellarCore, and **nothing
        // depends back on it**, which is what keeps `Catalog` brew-free (CS1) and
        // keeps SwiftData out of every other target.
        .target(
            name: "Persistence",
            dependencies: ["BrewClient"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "CellarTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
