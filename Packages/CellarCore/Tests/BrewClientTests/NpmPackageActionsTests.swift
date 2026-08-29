import Catalog
import Foundation
import Testing

@testable import BrewClient

/// The verbs an npm row and the npm detail pane offer, derived once from the
/// entry rather than restated per surface (`npm-source`).
@Suite("npm per-package actions")
struct NpmPackageActionsTests {
    private static func npm(_ name: String, outdated: Bool) -> InstalledPackage {
        let keg = InstalledKeg(version: "5.4.0", installedAt: nil, installedOnRequest: true)
        return InstalledPackage(
            kind: .npm,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            tap: nil,
            catalogVersion: outdated ? "5.5.0" : "5.4.0",
            kegs: [keg],
            primaryKeg: keg,
            snapshotOutdated: outdated,
            isPinned: false,
            pinnedVersion: nil,
            declaresAutoUpdates: nil
        )
    }

    private static func entry(_ package: InstalledPackage?) -> PackageEntry {
        PackageEntry(installed: package, catalog: nil, id: package?.id ?? PackageID(kind: .npm, name: "x"))
    }

    @Test("An outdated npm package offers Upgrade, then Uninstall")
    func outdatedOffersUpgradeThenUninstall() throws {
        let target = try #require(NpmPackageTarget(name: "typescript"))
        let actions = NpmCommand.available(for: Self.entry(Self.npm("typescript", outdated: true)))
        #expect(actions == [.upgrade(target), .uninstall(target)])
    }

    @Test("An up-to-date npm package offers only Uninstall")
    func currentOffersOnlyUninstall() throws {
        let target = try #require(NpmPackageTarget(name: "typescript"))
        let actions = NpmCommand.available(for: Self.entry(Self.npm("typescript", outdated: false)))
        #expect(actions == [.uninstall(target)])
    }

    @Test("A scoped name keeps its scope in every offered command")
    func scopedNameSurvives() throws {
        let actions = NpmCommand.available(for: Self.entry(Self.npm("@angular/cli", outdated: true)))
        #expect(actions.map(\.arguments) == [
            ["install", "-g", "@angular/cli@latest"],
            ["uninstall", "-g", "@angular/cli"]
        ])
    }

    @Test("A brew entry gets no npm verbs")
    func brewEntryGetsNothing() {
        let keg = InstalledKeg(version: "1", installedAt: nil, installedOnRequest: true)
        let formula = InstalledPackage(
            kind: .formula, name: "jq", displayName: "jq", desc: nil, homepage: nil, tap: nil,
            catalogVersion: "2", kegs: [keg], primaryKeg: keg, snapshotOutdated: true,
            isPinned: false, pinnedVersion: nil, declaresAutoUpdates: nil
        )
        #expect(NpmCommand.available(for: Self.entry(formula)).isEmpty)
    }

    @Test("A name npm could read as an option offers nothing rather than a disabled verb")
    func hostileNameOffersNothing() {
        #expect(NpmCommand.available(for: Self.entry(Self.npm("--force", outdated: true))).isEmpty)
    }

    @Test("An entry that is not installed offers nothing")
    func absentEntryOffersNothing() {
        #expect(NpmCommand.available(for: Self.entry(nil)).isEmpty)
    }
}
