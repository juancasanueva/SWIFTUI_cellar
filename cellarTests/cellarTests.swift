//
//  cellarTests.swift
//  cellarTests
//
//  Created by Juan Casanueva on 01/08/2026.
//

import Testing
import Catalog
@testable import cellar

struct cellarTests {
    @Test("A valid external handoff joins without collapsing a bulk selection")
    func validInstalledHandoffPreservesBulkSelection() {
        let first = PackageID(kind: .formula, name: "first")
        let second = PackageID(kind: .cask, name: "second")
        let handoff = PackageID(kind: .formula, name: "widget")
        let current: Set<PackageID> = [first, second]

        let adopted = InstalledSelection.adopting(
            handoff,
            into: current,
            available: current.union([handoff])
        )

        #expect(adopted == current.union([handoff]))
    }

    @Test("Nil and unavailable external identities leave bulk selection unchanged")
    func invalidInstalledHandoffPreservesBulkSelection() {
        let first = PackageID(kind: .formula, name: "first")
        let second = PackageID(kind: .cask, name: "second")
        let missing = PackageID(kind: .formula, name: "missing")
        let current: Set<PackageID> = [first, second]

        #expect(InstalledSelection.adopting(nil, into: current, available: current) == current)
        #expect(InstalledSelection.adopting(missing, into: current, available: current) == current)
    }

    @Test("Only the Updates lens seeds the Dependencies filter on")
    func updatesLensSeedsDependenciesFilter() {
        #expect(InstalledLens.updates.includesDependenciesByDefault)
        #expect(!InstalledLens.all.includesDependenciesByDefault)
        #expect(!InstalledLens.favorites.includesDependenciesByDefault)
    }

}
