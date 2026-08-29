import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The merge point. One inventory, two sources, and the property every existing
/// consumer already reads.
///
/// The rule with the sharpest edge is per-source isolation: each source's rows
/// are replaced only by that source's own next successful acquisition. A brew
/// failure that emptied the npm rows — or a `clear` that did — would make a
/// transient Homebrew problem look like a mass uninstall on the other side.
@MainActor
@Suite("Merged installed inventory", .timeLimit(.minutes(1)))
struct NpmInstalledStoreTests {
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    private static func npm(_ name: String, _ version: String, outdatedTo: String? = nil)
        -> InstalledPackage {
        NpmInventory(
            packages: [NpmGlobalPackage(name: name, version: version)],
            outdated: outdatedTo.map { latest in
                .fresh(
                    [name: NpmOutdatedRecord(current: version, wanted: latest, latest: latest)],
                    at: Date(timeIntervalSince1970: 0)
                )
            } ?? .notChecked(.notYetChecked)
        )
        .installedPackages()[0]
    }

    private static func store(_ answers: [FakeInstalledPayloadSource.Answer])
        -> (InstalledStore, FakeInstalledPayloadSource) {
        let source = FakeInstalledPayloadSource(answers)
        return (InstalledStore(source: source), source)
    }

    // MARK: - Recomposition

    @Test("An npm contribution joins the brew snapshot in one inventory")
    func npmContributionJoinsTheBrewSnapshot() async {
        let (store, _) = Self.store([.formulae(["wget"])])

        await store.refresh(using: TestInstallation.appleSilicon)
        store.adopt([Self.npm("typescript", "5.6.2")], from: .npm)

        #expect(store.inventory.packages.map(\.name) == ["typescript", "wget"])
        #expect(store.inventory.installedIDs.contains(PackageID(kind: .npm, name: "typescript")))
        #expect(store.inventory.installedIDs.contains(PackageID(kind: .formula, name: "wget")))
    }

    @Test("A later brew snapshot keeps the npm contribution")
    func brewRefreshKeepsNpmRows() async {
        let (store, _) = Self.store([.formulae(["wget"]), .formulae(["wget", "curl"])])

        await store.refresh(using: TestInstallation.appleSilicon)
        store.adopt([Self.npm("typescript", "5.6.2")], from: .npm)
        store.invalidate()
        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(store.inventory.packages.map(\.name) == ["curl", "typescript", "wget"])
    }

    @Test("A second npm adoption replaces the first, and only the npm rows")
    func npmAdoptionReplacesOnlyItsOwnRows() async {
        let (store, _) = Self.store([.formulae(["wget"])])
        await store.refresh(using: TestInstallation.appleSilicon)

        store.adopt([Self.npm("typescript", "5.6.2"), Self.npm("corepack", "0.29.4")], from: .npm)
        store.adopt([Self.npm("typescript", "5.7.0")], from: .npm)

        #expect(store.inventory.packages.map(\.name) == ["typescript", "wget"])
        #expect(
            store.inventory.package(PackageID(kind: .npm, name: "typescript"))?.installedVersion
                == "5.7.0"
        )
    }

    // MARK: - Ordering

    @Test("Rows sharing a name order formula, cask, then npm")
    func mergedRowsUseTheRankOrder() async {
        let (store, _) = Self.store([.formulae(["typescript"])])

        await store.refresh(using: TestInstallation.appleSilicon)
        store.adopt([Self.npm("typescript", "5.6.2")], from: .npm)

        #expect(store.inventory.packages.map(\.kind) == [.formula, .npm])
        #expect(store.inventory.packages.count == 2)
    }

    // MARK: - The outdated set

    @Test("An outdated npm package joins the one outdated set every surface reads")
    func outdatedIDsIsTheUnion() async {
        let (store, _) = Self.store([.formulae(["wget"])])

        await store.refresh(using: TestInstallation.appleSilicon)
        store.adopt(
            [
                Self.npm("typescript", "5.6.2", outdatedTo: "5.7.0"),
                Self.npm("corepack", "0.29.4"),
            ],
            from: .npm
        )

        #expect(store.inventory.outdatedIDs == [PackageID(kind: .npm, name: "typescript")])
        #expect(store.inventory.outdatedCount == 1)
    }

    // MARK: - Per-source isolation

    @Test("A failed brew acquisition leaves the npm rows in place")
    func brewFailureDoesNotEvictNpm() async {
        let (store, _) = Self.store([.formulae(["wget"]), .failure(.malformedPayload)])

        await store.refresh(using: TestInstallation.appleSilicon)
        store.adopt([Self.npm("typescript", "5.6.2")], from: .npm)
        store.invalidate()
        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(store.state == .failed(.malformedPayload))
        // Both survive: brew keeps its last good snapshot, npm keeps its rows.
        #expect(store.inventory.packages.map(\.name) == ["typescript", "wget"])
    }

    @Test("Homebrew going absent clears the brew rows and keeps the npm rows")
    func brewAbsenceKeepsNpmContributions() async {
        let (store, _) = Self.store([.formulae(["wget"])])

        await store.refresh(using: TestInstallation.appleSilicon)
        store.adopt([Self.npm("typescript", "5.6.2")], from: .npm)
        await store.refresh(for: .absent)

        #expect(store.absence != nil)
        #expect(store.inventory.packages.map(\.name) == ["typescript"])
        #expect(store.inventory.installedIDs == [PackageID(kind: .npm, name: "typescript")])
    }

    @Test("Turning the npm source off removes exactly the npm rows")
    func clearingNpmLeavesBrewIntact() async {
        let (store, _) = Self.store([.formulae(["wget"])])

        await store.refresh(using: TestInstallation.appleSilicon)
        store.adopt([Self.npm("typescript", "5.6.2")], from: .npm)
        store.clearContributions(from: .npm)

        #expect(store.inventory.packages.map(\.name) == ["wget"])
        #expect(store.state == .loaded)
    }

    @Test("With the npm source never enabled the inventory is byte-identical to brew's")
    func npmOffIsIdenticalToBrewOnly() async {
        let (withNpm, _) = Self.store([.formulae(["wget", "curl"])])
        let (brewOnly, _) = Self.store([.formulae(["wget", "curl"])])

        await withNpm.refresh(using: TestInstallation.appleSilicon)
        await brewOnly.refresh(using: TestInstallation.appleSilicon)

        #expect(withNpm.inventory == brewOnly.inventory)
        #expect(withNpm.inventory.outdatedIDs == brewOnly.inventory.outdatedIDs)
    }

    @Test("An npm adoption before any brew snapshot stands on its own")
    func npmCanArriveFirst() {
        let (store, _) = Self.store([.formulae([])])

        store.adopt([Self.npm("typescript", "5.6.2")], from: .npm)

        #expect(store.inventory.packages.map(\.name) == ["typescript"])
        #expect(store.inventory.isEmpty == false)
    }

    @Test("Adopting an empty list from npm empties only the npm rows")
    func emptyNpmAdoptionIsNotAClear() async {
        let (store, _) = Self.store([.formulae(["wget"])])
        await store.refresh(using: TestInstallation.appleSilicon)
        store.adopt([Self.npm("typescript", "5.6.2")], from: .npm)

        store.adopt([], from: .npm)

        #expect(store.inventory.packages.map(\.name) == ["wget"])
    }

    @Test("The brew snapshot's skipped-record count survives recomposition")
    func skippedRecordCountIsPreserved() async {
        let source = FakeInstalledPayloadSource([
            .payload(
                #"{"formulae":[{"name":42,"installed":"not a formula"}],"casks":[]}"#
            )
        ])
        let store = InstalledStore(source: source)

        await store.refresh(using: TestInstallation.appleSilicon)
        let skippedBefore = store.inventory.skippedRecordCount
        store.adopt([Self.npm("typescript", "5.6.2")], from: .npm)

        #expect(skippedBefore == 1)
        #expect(store.inventory.skippedRecordCount == 1)
    }
}
