//
//  CleanupStorageBytesTests.swift
//  cellarTests
//

import Catalog
import DiskUsage
import Foundation
import Testing

@testable import cellar

/// The byte totals behind the Cleanup storage bar, pure over the snapshot.
///
/// The one rule worth a test of its own is the double-count guard: a
/// Homebrew-installed node keeps its global packages inside its own keg, so
/// the npm segment would otherwise repeat bytes the Cellar segment already
/// shows. The guard moves them, never invents or drops them.
@Suite("Cleanup storage bytes")
struct CleanupStorageBytesTests {
    private static let cellar = "/opt/homebrew/Cellar"

    private static func snapshot(
        npmGlobals path: String?,
        npmBytes: Int64,
        packages: [DiskPackageUsage] = []
    ) -> DiskUsageSnapshot {
        DiskUsageSnapshot(
            roots: DiskRootsIdentity(
                cellar: cellar,
                caskroom: "/opt/homebrew/Caskroom",
                cache: "/Users/tester/Library/Caches/Homebrew",
                npmGlobals: path
            ),
            generatedAt: Date(timeIntervalSince1970: 1_000_000),
            rootStates: [.cellar: .present, .caskroom: .present, .cache: .present],
            packages: packages,
            cache: DiskObservation(allocatedBytes: 500, logicalBytes: 500),
            npmGlobals: DiskObservation(allocatedBytes: npmBytes, logicalBytes: npmBytes)
        )
    }

    private static func formula(
        _ name: String, bytes: Int64, linkState: FormulaLinkState = .linked("1")
    ) -> DiskPackageUsage {
        let id = PackageID(kind: .formula, name: name)
        return DiskPackageUsage(id: id, versions: [
            DiskVersionUsage(
                id: DiskVersionID(package: id, rawVersion: "1"),
                observation: DiskObservation(allocatedBytes: bytes, logicalBytes: bytes),
                linkState: linkState
            ),
        ])
    }

    @Test("Globals outside the Cellar are their own segment and leave the Cellar whole")
    func globalsOutsideTheCellarAreSeparate() {
        let packages = [Self.formula("node", bytes: 1_000)]
        let bytes = CleanupStorageBytes(
            packages: packages,
            snapshot: Self.snapshot(npmGlobals: "/Users/tester/.npm-global/lib/node_modules", npmBytes: 300, packages: packages)
        )

        #expect(bytes.cellar == 1_000)
        #expect(bytes.npmGlobals == 300)
        #expect(bytes.cache == 500)
    }

    @Test("Globals inside the Cellar move out of the Cellar segment rather than repeating")
    func globalsInsideTheCellarAreSubtracted() {
        let packages = [Self.formula("node", bytes: 1_000)]
        let bytes = CleanupStorageBytes(
            packages: packages,
            snapshot: Self.snapshot(npmGlobals: "\(Self.cellar)/node/24.1.0/lib/node_modules", npmBytes: 300, packages: packages)
        )

        #expect(bytes.cellar == 700)
        #expect(bytes.npmGlobals == 300)
        #expect(bytes.cellar + bytes.npmGlobals == 1_000)
    }

    /// A snapshot mid-refresh can pair an old Cellar total with a new npm one;
    /// the bar must never render a negative width from that.
    @Test("The Cellar segment clamps at zero when the overlap exceeds it")
    func overlapClampsAtZero() {
        let packages = [Self.formula("node", bytes: 100)]
        let bytes = CleanupStorageBytes(
            packages: packages,
            snapshot: Self.snapshot(npmGlobals: "\(Self.cellar)/node/24.1.0/lib/node_modules", npmBytes: 300, packages: packages)
        )

        #expect(bytes.cellar == 0)
        #expect(bytes.npmGlobals == 300)
    }

    @Test("Unlinked kegs stay split out and are untouched by the guard")
    func unlinkedKegsAreUntouched() {
        let packages = [
            Self.formula("node", bytes: 1_000),
            Self.formula("openssl", bytes: 200, linkState: .unlinked),
        ]
        let bytes = CleanupStorageBytes(
            packages: packages,
            snapshot: Self.snapshot(npmGlobals: "\(Self.cellar)/node/24.1.0/lib/node_modules", npmBytes: 300, packages: packages)
        )

        #expect(bytes.cellar == 700)
        #expect(bytes.unlinked == 200)
    }

    @Test("Without npm configured the npm segment is zero and nothing else changes")
    func unconfiguredNpmIsZero() {
        let packages = [Self.formula("node", bytes: 1_000)]
        let bytes = CleanupStorageBytes(
            packages: packages,
            snapshot: Self.snapshot(npmGlobals: nil, npmBytes: 0, packages: packages)
        )

        #expect(bytes.cellar == 1_000)
        #expect(bytes.npmGlobals == 0)
    }

    @Test("Without a snapshot only the package totals survive")
    func withoutASnapshotOnlyPackagesCount() {
        let bytes = CleanupStorageBytes(packages: [Self.formula("node", bytes: 1_000)], snapshot: nil)

        #expect(bytes.cellar == 1_000)
        #expect(bytes.cache == 0)
        #expect(bytes.npmGlobals == 0)
    }
}
