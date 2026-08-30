//
//  CleanupRowTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import Testing

@testable import cellar

/// What the storage list says a package is, and which rows may carry brew's
/// cleanup pills.
@Suite("Cleanup row")
struct CleanupRowTests {
    /// Every row in the storage list is marked, formulae included. Casks and
    /// npm globals still defer to the shared `PackageKindTag`; the formula pill
    /// is this list's own, because here formulae are not the silent majority
    /// they are in the Installed list.
    @Test(
        "Every kind gets a pill in the storage list",
        arguments: [
            (PackageKind.formula, cellar.CleanupRow.KindPill.formula),
            (.cask, .shared(.cask)),
            (.npm, .shared(.npm)),
        ]
    )
    func kindPills(kind: PackageKind, pill: cellar.CleanupRow.KindPill) {
        #expect(cellar.CleanupRow.kindPill(for: kind) == pill)
    }

    /// The pills exist only for a `PackageTarget`, and brew's target refuses
    /// npm at the source guard — so an npm row can never offer a Preview.
    @Test("An npm package is never a cleanup target")
    func npmIsNeverACleanupTarget() {
        #expect(PackageTarget(PackageID(kind: .npm, name: "typescript")) == nil)
        #expect(PackageTarget(PackageID(kind: .formula, name: "wget")) != nil)
    }
}
