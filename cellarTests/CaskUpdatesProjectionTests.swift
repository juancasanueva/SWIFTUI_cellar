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

    // MARK: - Self-updating apps

    @Test("Self-updating casks join only when asked, and only when behind")
    func selfUpdatingCasksJoinOnlyWhenAskedAndBehind() {
        let inventory = InstalledInventory(packages: [
            Self.installed(.cask, "chrome", outdated: true, autoUpdates: true),
            Self.installed(.cask, "ghostty", outdated: true, autoUpdates: true),
            Self.installed(.cask, "vlc", outdated: true),
        ])
        let behind: (InstalledPackage) -> Bool = { $0.name == "chrome" }

        let without = CaskUpdatesProjection.casks(in: inventory, catalog: { _ in nil }, selfUpdatingBehind: nil)
        let with = CaskUpdatesProjection.casks(in: inventory, catalog: { _ in nil }, selfUpdatingBehind: behind)

        #expect(without.map(\.name) == ["vlc"])
        #expect(with.map(\.name) == ["chrome", "vlc"])
    }

    @Test("An app on disk at the latest version is current, whatever brew recorded")
    func anAppAtTheLatestVersionIsCurrent() {
        #expect(CaskAppVersion.isBehind(shortVersion: "1.4.0", bundleVersion: "12345", catalogVersion: "1.4.0") == false)
        #expect(CaskAppVersion.isBehind(shortVersion: "5.2.7", bundleVersion: "32913", catalogVersion: "5.2.7.32913") == false)
        #expect(CaskAppVersion.isBehind(shortVersion: "2.0", bundleVersion: nil, catalogVersion: "2.0,345") == false)
        #expect(CaskAppVersion.isBehind(shortVersion: "158.0", bundleVersion: nil, catalogVersion: "157.0.8103.39") == false)
    }

    @Test("An app on disk below the latest version is behind")
    func anAppBelowTheLatestVersionIsBehind() {
        #expect(CaskAppVersion.isBehind(shortVersion: "156.0.8078.48", bundleVersion: "8078.48", catalogVersion: "157.0.8103.39") == true)
        #expect(CaskAppVersion.isBehind(shortVersion: "5.2.5", bundleVersion: "32528", catalogVersion: "5.2.7.32913") == true)
        #expect(CaskAppVersion.isBehind(shortVersion: "1.9", bundleVersion: nil, catalogVersion: "1.10") == true)
    }

    @Test("With no short version the bundle version decides; with neither, nothing does")
    func theBundleVersionDecidesAlone() {
        #expect(CaskAppVersion.isBehind(shortVersion: nil, bundleVersion: "41", catalogVersion: "42") == true)
        #expect(CaskAppVersion.isBehind(shortVersion: nil, bundleVersion: "42", catalogVersion: "42") == false)
        #expect(CaskAppVersion.isBehind(shortVersion: nil, bundleVersion: nil, catalogVersion: "42") == nil)
    }

    // MARK: - Formulae

    @Test("The formula page lists outdated formulae only")
    func theFormulaPageListsOutdatedFormulaeOnly() {
        let inventory = InstalledInventory(packages: [
            Self.installed(.formula, "wget", outdated: true),
            Self.installed(.formula, "jq", outdated: false),
            Self.installed(.cask, "vlc", outdated: true),
            Self.installed(.formula, "git", outdated: true),
        ])

        let formulae = CaskUpdatesProjection.packages(of: .formula, in: inventory, catalog: { _ in nil })

        #expect(formulae.map(\.name) == ["git", "wget"])
        #expect(formulae.allSatisfy { $0.kind == .formula })
    }

    @Test("A pinned formula is not listed: brew upgrade refuses it")
    func aPinnedFormulaIsNotListed() {
        let inventory = InstalledInventory(packages: [
            Self.installed(.formula, "node", outdated: true, pinned: true),
            Self.installed(.formula, "wget", outdated: true),
        ])

        let formulae = CaskUpdatesProjection.packages(of: .formula, in: inventory, catalog: { _ in nil })

        #expect(formulae.map(\.name) == ["wget"])
    }

    // MARK: - Fixtures

    private static func installed(
        _ kind: PackageKind,
        _ name: String,
        outdated: Bool,
        autoUpdates: Bool? = nil,
        displayName: String? = nil,
        desc: String? = nil,
        tap: String? = "homebrew/cask",
        pinned: Bool = false
    ) -> InstalledPackage {
        let keg = InstalledKeg(version: "1.0", installedAt: nil, installedOnRequest: true)
        return InstalledPackage(
            kind: kind, name: name, displayName: displayName ?? name, desc: desc,
            homepage: nil, tap: tap, catalogVersion: "2.0", kegs: [keg], primaryKeg: keg,
            snapshotOutdated: outdated, isPinned: pinned, pinnedVersion: nil,
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
