//
//  NpmAppKindArmsTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import DiskUsage
import Foundation
import Testing

@testable import cellar

/// The two app-target switches over `PackageKind` that the npm kind reaches.
///
/// Both answer "not this one", but they have to answer it explicitly: a
/// `default:` here would have silently pointed the artifact scanner at a
/// Homebrew Cellar path for an npm package, and let the Homebrew-update prompt
/// count npm globals as evidence that `brew update` is overdue.
@Suite("npm arms of the app-target kind switches")
struct NpmAppKindArmsTests {
    private static func package(_ kind: PackageKind, _ name: String, tap: String?) -> InstalledPackage {
        let keg = InstalledKeg(
            version: "1.0.0",
            installedAt: Date(timeIntervalSince1970: 0),
            installedOnRequest: true
        )
        return InstalledPackage(
            kind: kind,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            tap: tap,
            catalogVersion: "1.0.0",
            kegs: [keg],
            primaryKeg: keg,
            snapshotOutdated: false,
            isPinned: false,
            pinnedVersion: nil,
            declaresAutoUpdates: nil
        )
    }

    @Test("An npm package contributes no artifact to assess")
    func npmYieldsNoArtifactLocation() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("npm-arms-\(UUID().uuidString)")
        let cellarRoot = root.appendingPathComponent("Cellar")
        let caskroom = root.appendingPathComponent("Caskroom")
        let binary = cellarRoot
            .appendingPathComponent("typescript/1.0.0/bin")
            .appendingPathComponent("tsc")
        try FileManager.default.createDirectory(
            at: binary.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // A real Mach-O, because the locator only reports what it can classify:
        // a shell script would produce an empty list for the formula too, and
        // the npm assertion would then prove nothing.
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/echo"), to: binary)
        defer { try? FileManager.default.removeItem(at: root) }

        let locator = ArtifactLocator(cellar: cellarRoot, caskroom: caskroom)

        // The same name, under both kinds. The formula reaches a real keg on
        // disk; the npm entry must not, even though the path would resolve.
        let formulaLocations = locator.locations(
            for: [Self.package(.formula, "typescript", tap: "homebrew/core")]
        )
        let npmLocations = locator.locations(
            for: [Self.package(.npm, "typescript", tap: nil)]
        )

        #expect(formulaLocations.map(\.url.lastPathComponent) == ["tsc"])
        #expect(npmLocations.isEmpty)
    }

    @Test("An npm version disagreement is not evidence that brew update is overdue")
    func npmNeverTestifiesThatBrewIsBehind() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Both packages disagree with the catalog by the same amount. Only the
        // core formula is entitled to say so.
        let published: (PackageID) -> String? = { _ in "2.0.0" }

        let fromFormula = HomebrewUpdateNeed.isBehind(
            packages: [Self.package(.formula, "wget", tap: "homebrew/core")],
            catalogVersion: published,
            catalogDownloadedAt: now,
            lastUpdate: .read(now),
            now: now
        )
        let fromNpm = HomebrewUpdateNeed.isBehind(
            packages: [Self.package(.npm, "typescript", tap: nil)],
            catalogVersion: published,
            catalogDownloadedAt: now,
            lastUpdate: .read(now),
            now: now
        )

        #expect(fromFormula)
        #expect(fromNpm == false)
    }

    @Test("An npm package does not count as a comparison the age fallback must yield to")
    func npmDoesNotSuppressTheAgeFallback() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stale = now.addingTimeInterval(-(HealthThresholds.lastUpdateFreshSeconds + 60))

        // The catalog can answer for this identity, so if the npm entry were
        // treated as comparable the marker's age would never be reached and a
        // genuinely stale Homebrew would go unreported.
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [Self.package(.npm, "typescript", tap: nil)],
            catalogVersion: { _ in "1.0.0" },
            catalogDownloadedAt: now,
            lastUpdate: .read(stale),
            now: now
        )

        #expect(behind)
    }
}
