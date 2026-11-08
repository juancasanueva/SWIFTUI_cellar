//
//  CaskUpdatesProjectionTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import Foundation
import Testing

@testable import cellar

/// The Cask Updates page lists exactly the installed casks Cellar reports as
/// outdated — the same set the Updates badge counts — and never drops one just
/// because the catalog has no record for it.
@Suite("Cask updates projection")
struct CaskUpdatesProjectionTests {
    @Test("Only outdated casks are listed, by name")
    func onlyOutdatedCasksAreListed() {
        let inventory = InstalledInventory(packages: [
            Self.installed(.cask, "zed", outdated: true),
            Self.installed(.cask, "firefox", outdated: false),
            Self.installed(.formula, "wget", outdated: true),
            Self.installed(.cask, "arc", outdated: true),
        ])

        let casks = CaskUpdatesProjection.casks(in: inventory, catalog: { _ in nil })

        #expect(casks.map(\.name) == ["arc", "zed"])
        #expect(casks.allSatisfy { $0.kind == .cask })
    }

    @Test("A self-updating cask is not listed, matching the outdated set")
    func aSelfUpdatingCaskIsNotListed() {
        let inventory = InstalledInventory(packages: [
            Self.installed(.cask, "chrome", outdated: true, autoUpdates: true),
            Self.installed(.cask, "vlc", outdated: true),
        ])

        let casks = CaskUpdatesProjection.casks(in: inventory, catalog: { _ in nil })

        #expect(casks.map(\.name) == ["vlc"])
    }

    @Test("The catalog record is preferred when the catalog has one")
    func theCatalogRecordIsPreferred() {
        let inventory = InstalledInventory(packages: [Self.installed(.cask, "vlc", outdated: true)])
        let record = Self.catalogRecord("vlc", desc: "Multimedia player", installs: 42)

        let casks = CaskUpdatesProjection.casks(in: inventory, catalog: { $0 == record.id ? record : nil })

        #expect(casks == [record])
    }

    @Test("A cask the catalog lacks is drawn from its installed record")
    func aCaskTheCatalogLacksIsDrawnFromItsInstalledRecord() throws {
        let inventory = InstalledInventory(packages: [
            Self.installed(.cask, "supacode", outdated: true, displayName: "supacode", desc: "Agents", tap: nil),
        ])

        let cask = try #require(CaskUpdatesProjection.casks(in: inventory, catalog: { _ in nil }).first)

        #expect(cask.id == PackageID(kind: .cask, name: "supacode"))
        #expect(cask.displayName == "supacode")
        #expect(cask.desc == "Agents")
        #expect(cask.version == "2.0")
        #expect(cask.installCount365d == nil)
    }

    // MARK: - Fixtures

    private static func installed(
        _ kind: PackageKind,
        _ name: String,
        outdated: Bool,
        autoUpdates: Bool? = nil,
        displayName: String? = nil,
        desc: String? = nil,
        tap: String? = "homebrew/cask"
    ) -> InstalledPackage {
        let keg = InstalledKeg(version: "1.0", installedAt: nil, installedOnRequest: true)
        return InstalledPackage(
            kind: kind, name: name, displayName: displayName ?? name, desc: desc,
            homepage: nil, tap: tap, catalogVersion: "2.0", kegs: [keg], primaryKeg: keg,
            snapshotOutdated: outdated, isPinned: false, pinnedVersion: nil,
            declaresAutoUpdates: autoUpdates
        )
    }

    private static func catalogRecord(_ name: String, desc: String, installs: Int) -> CatalogPackage {
        CatalogPackage(
            kind: .cask, name: name, displayName: name.uppercased(), desc: desc,
            homepage: nil, license: nil, version: "2.0", tap: "homebrew/cask",
            dependencies: [], buildDependencies: [], dependents: [], caveats: nil,
            deprecated: false, deprecationReason: nil, deprecationDate: nil,
            disabled: false, disableReason: nil, disableDate: nil,
            autoUpdates: false, installCount365d: installs
        )
    }
}
