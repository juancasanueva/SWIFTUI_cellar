// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CellarCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "BrewProcess", targets: ["BrewProcess"]),
        .library(name: "Catalog", targets: ["Catalog"]),
        .library(name: "DiskUsage", targets: ["DiskUsage"]),
        .library(name: "BrewClient", targets: ["BrewClient"]),
        .library(name: "SecurityKit", targets: ["SecurityKit"]),
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
            resources: [.copy("Discovery")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CatalogTests",
            dependencies: ["Catalog", "CellarTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DiskUsage",
            dependencies: ["BrewProcess", "Catalog"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DiskUsageTests",
            dependencies: ["DiskUsage", "CellarTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The only target that sees both libraries. The edge is one-directional:
        // nothing depends back on it, so `Catalog` stays brew-free (design D1).
        .target(
            name: "BrewClient",
            dependencies: ["BrewProcess", "Catalog", "DiskUsage"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BrewClientTests",
            dependencies: ["BrewClient", "CellarTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Advisory scanning and artifact integrity. Deliberately no dependency on
        // `BrewProcess`, `BrewClient` or `DiskUsage`: the capability reads
        // advisories over HTTP and matches them against values, so it never needs
        // a `brew` binary, a subprocess or a disk walk. That absence is also what
        // keeps the strict-SemVer comparator it owns **structurally unreachable**
        // from the snooze rule in `BrewClient` (local-package-metadata LPM5) —
        // the edge is missing in this direction *and* in the reverse one. Every
        // composition point between the two lives in the app target, because no
        // target here may see both.
        .target(
            name: "SecurityKit",
            dependencies: ["Catalog"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SecurityKitTests",
            dependencies: ["SecurityKit", "CellarTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The outermost node of the graph (design D1): it sees `BrewClient` so the
        // history draft -> row mapping stays testable in CellarCore, and it sees
        // `SecurityKit` for the `DismissedCVE` model alone. **Nothing depends back
        // on it**, which is what keeps `Catalog` brew-free (CS1) and keeps
        // SwiftData out of every other target. It is the only target with both
        // inward edges, and `DismissalStore.swift` is the only file in it that
        // imports `SecurityKit` — asserted exhaustively, not by convention.
        .target(
            name: "Persistence",
            dependencies: ["BrewClient", "SecurityKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "CellarTestSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
