//
//  MenuBarCompositionTests.swift
//  cellarTests
//

import Foundation
import Testing

@testable import cellar

/// The shapes that derive a *collection or a count* of outdated packages
/// without going through the one snooze-aware projection.
///
/// Deliberately blind to per-package reads such as `installed.isOutdated` or
/// `entry.installed?.isOutdated`: the requirement is about deriving a count or
/// a set, never about reading one package's own flag, and a bare-token scan
/// would condemn twenty legitimate call sites
/// (installed-inventory spec:77-85).
private enum OutdatedDerivation {
    /// A collection filtered by the per-package flag — the shape the sidebar
    /// badge and the Home attention card shipped with.
    static let filterShapes = [
        "filter(\\.isOutdated)",
        "filter { $0.isOutdated",
        "filter { package in package.isOutdated",
    ]

    /// The inventory's own un-snoozed answers. Legitimate only when they are
    /// the projection's, which is exactly what the `(metadata:` argument makes
    /// visible at the call site.
    static let projectionTokens = [".outdatedIDs", ".outdatedCount"]

    /// The argument label that marks a delegated read.
    static let delegatedPrefix = "(metadata:"

    /// Every self-computed derivation in `code`, named by the shape that
    /// matched. Empty means the source announces no number of its own.
    static func derivations(in code: String) -> [String] {
        var found: [String] = []
        for shape in filterShapes where code.contains(shape) {
            found.append(shape)
        }
        for token in projectionTokens {
            var cursor = code.startIndex
            while let range = code.range(of: token, range: cursor..<code.endIndex) {
                if !code[range.upperBound...].hasPrefix(delegatedPrefix) {
                    found.append(token)
                }
                cursor = range.upperBound
            }
        }
        return found
    }
}

/// The menu bar's composition claims, and the app-wide sweep that keeps the
/// outdated number single-sourced.
///
/// Every claim here is an assertion over the repository's own sources, read off
/// disk in the shipped `AppSecuritySources` idiom: a claim about what the app
/// target does *not* contain cannot be made by importing it.
@Suite("Menu-bar composition")
struct MenuBarCompositionTests {
    // MARK: - T18 — the app-wide sweep (installed-inventory spec:77)

    /// No surface in the app announces a self-computed outdated count.
    ///
    /// The detector is anchored positively in the same test: handed the exact
    /// literal the sidebar shipped with, it must match. A detector that stopped
    /// recognising anything would otherwise report a clean sweep forever.
    @Test("No surface in the app announces a self-computed outdated count")
    func noSurfaceInTheAppAnnouncesASelfComputedOutdatedCount() throws {
        // Positive anchor first: the detector recognises the shipped literal.
        let shipped = "installed.inventory.packages.filter(\\.isOutdated).count"
        #expect(
            OutdatedDerivation.derivations(in: shipped).isEmpty == false,
            "the detector no longer recognises the shape it exists to find"
        )
        // And it separates a delegated read from a raw one.
        #expect(OutdatedDerivation.derivations(in: "browse.outdatedCount(metadata: lookup)").isEmpty)
        #expect(OutdatedDerivation.derivations(in: "browse.outdatedIDs(metadata: lookup)").isEmpty)
        #expect(
            OutdatedDerivation.derivations(in: "inventory.outdatedCount").isEmpty == false,
            "an un-snoozed count read straight off the inventory went unnoticed"
        )

        let sources = try AppSecuritySources.load()
        #expect(sources.count > 40, "the app sweep enumerated only \(sources.count) sources")

        var offenders: [String] = []
        for source in sources {
            for shape in OutdatedDerivation.derivations(in: source.code) {
                offenders.append("\(source.name): \(shape)")
            }
        }
        #expect(offenders.isEmpty, "self-computed outdated derivations: \(offenders)")
    }
}
