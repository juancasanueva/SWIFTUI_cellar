//
//  NpmInstalledChromeTests.swift
//  cellarTests
//

import BrewClient
import BrewProcess
import Catalog
import Foundation
import Testing

@testable import cellar

/// The Installed surface's npm chrome: the Source chip, the NPM pill, and the
/// one line that decides whether the list has anything to say.
///
/// Every rule here is a projection the views read. `InstalledBrowse.isAvailable`
/// is the one worth spelling out: it used to be "Homebrew loaded", and with a
/// second source that is wrong in a way nothing would have caught — an npm-only
/// machine has a genuine inventory, and reporting it unavailable collapses every
/// installed-state filter to "all" over rows that are really there.
@MainActor
@Suite("npm installed chrome")
struct NpmInstalledChromeTests {
    private static func npmRow(_ name: String) -> InstalledPackage {
        NpmInventory(
            packages: [NpmGlobalPackage(name: name, version: "1.0.0")],
            outdated: .notChecked(.notYetChecked)
        )
        .installedPackages()[0]
    }

    /// A store fed by a scripted payload. `FakeInstalledPayloadSource` lives in
    /// the package's own test target, so the app target gets the smallest thing
    /// that answers one document.
    private static func store(brew: [String]) -> InstalledStore {
        InstalledStore(source: ScriptedInstalledPayload(formulae: brew))
    }

    private static let installation = BrewInstallation(
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
        prefix: .appleSilicon,
        version: BrewVersion(major: 4, minor: 0, patch: 0)
    )

    // MARK: - The one line

    @Test("The inventory is available when brew loaded, npm contributes, or both")
    func availabilityIsEitherSource() async {
        let both = Self.store(brew: ["wget"])
        await both.refresh(using: Self.installation)
        both.adopt([Self.npmRow("typescript")], from: .npm)

        let brewOnly = Self.store(brew: ["wget"])
        await brewOnly.refresh(using: Self.installation)

        let npmOnly = Self.store(brew: [])
        await npmOnly.refresh(for: .absent)
        npmOnly.adopt([Self.npmRow("typescript")], from: .npm)

        #expect(both.hasAnyInventory)
        #expect(brewOnly.hasAnyInventory)
        // The case the old rule got wrong: Homebrew is absent, and there is
        // still a real inventory to filter.
        #expect(npmOnly.hasAnyInventory)
    }

    @Test("With Homebrew absent and no npm rows the inventory is unavailable")
    func neitherSourceIsUnavailable() async {
        let store = Self.store(brew: [])

        await store.refresh(for: .absent)

        #expect(store.hasAnyInventory == false)
        #expect(store.absence != nil)
    }

    @Test("Withdrawing the npm rows from an npm-only inventory makes it unavailable again")
    func withdrawingTheLastSourceIsUnavailable() async {
        let store = Self.store(brew: [])
        await store.refresh(for: .absent)
        store.adopt([Self.npmRow("typescript")], from: .npm)
        #expect(store.hasAnyInventory)

        store.clearContributions(from: .npm)

        #expect(store.hasAnyInventory == false)
    }

    // MARK: - The Source chip

    @Test("Each unavailable reason has guidance of its own that names npm")
    func chipGuidanceIsPerReason() {
        let guidance = NpmSourceUnavailableReason.allCases.map(\.guidance)

        #expect(NpmSourceUnavailableReason.disabled.guidance
            == "Turn the npm source on in Settings to filter by source")
        #expect(NpmSourceUnavailableReason.absent.guidance
            == "npm was not detected on this Mac")
        #expect(NpmSourceUnavailableReason.invalid.guidance
            == "The npm path configured in Settings did not work")
        // Distinct, non-empty, and every one of them says npm rather than
        // Homebrew — the chip is about npm and a brew-worded refusal would send
        // the user to the wrong place.
        #expect(Set(guidance).count == NpmSourceUnavailableReason.allCases.count)
        #expect(guidance.allSatisfy { $0.contains("npm") })
        #expect(guidance.contains { $0.contains("Homebrew") } == false)
    }

    @Test("An available source has no guidance to show")
    func availableSourceHasNoGuidance() {
        let browse = InstalledBrowse(
            inventory: .empty, isAvailable: true, npmSource: .available
        )

        #expect(browse.sourceUnavailableReason?.guidance == nil)
        #expect(browse.isSourceFilterEnabled)
    }

    // MARK: - The pill

    @Test("Only an npm row carries the NPM pill, and only a cask the CASK one")
    func pillFollowsKind() {
        let npm = Self.npmRow("typescript")

        #expect(npm.kindTag == .npm)
        #expect(npm.kindTag?.label == "NPM")
        #expect(PackageKindTag(kind: .formula) == nil)
        #expect(PackageKindTag(kind: .cask)?.label == "CASK")
    }

    @Test("A row's accessibility identifier names its own kind")
    func rowIdentifierNamesTheKind() {
        #expect(InstalledRow.identifier(for: PackageID(kind: .formula, name: "wget"))
            == "installed-row-formula-wget")
        #expect(InstalledRow.identifier(for: PackageID(kind: .cask, name: "iterm2"))
            == "installed-row-cask-iterm2")
        // The old two-way ternary labelled everything that was not a formula a
        // cask, so an npm row would have been addressable as
        // `installed-row-cask-typescript` — a UI test asserting on casks would
        // have started matching npm packages.
        #expect(InstalledRow.identifier(for: PackageID(kind: .npm, name: "typescript"))
            == "installed-row-npm-typescript")
    }

    // MARK: - Mutation affordances

    @Test("No brew mutation affordance is available for an npm row")
    func npmRowsOfferNoBrewMutation() {
        let id = PackageID(kind: .npm, name: "typescript")

        // Pin, reinstall, zap and upgrade all go through `PackageTarget`, so a
        // failing init removes every one of them at once rather than four
        // separate view conditions that could drift.
        #expect(PackageTarget(id) == nil)
        #expect(FormulaID(id) == nil)
        #expect(CaskID(id) == nil)
    }

    @Test("An npm detail pane shows one version row and no tap")
    func npmDetailIsMinimal() {
        let detail = InstalledDetailProjection(Self.npmRow("typescript"))

        #expect(detail.installStateFacts.map(\.label) == ["Version"])
        #expect(detail.tapOfOrigin == nil)
        #expect(detail.orderedFacts.map(\.label) == ["Type", "Version"])
    }
}

/// One canned `brew info --installed --json=v2` document.
private struct ScriptedInstalledPayload: InstalledPayloadSourcing {
    let formulae: [String]

    func payload(using installation: BrewInstallation) async throws(InstalledInventoryError) -> Data {
        let records = formulae.map {
            """
            {"name":"\($0)","tap":"homebrew/core","versions":{"stable":"1.0.0"},\
            "installed":[{"version":"1.0.0","time":1700000000,\
            "installed_on_request":true}],"outdated":false}
            """
        }
        return Data("{\"formulae\":[\(records.joined(separator: ","))],\"casks\":[]}".utf8)
    }
}
