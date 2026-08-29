import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The `BrewClient` half of the exhaustiveness rules. Its sibling lives in
/// `CatalogTests`, because `CatalogTests` cannot see `BrewClient` and must not
/// be given the edge just to keep one file whole (`Package.swift`: the catalog
/// stays brew-free, so the split is the build graph's, not a preference).
@Suite("npm arms of the shared kind switches")
struct NpmKindExhaustivenessTests {
    @Test("An npm entry is outdated exactly when its snapshot says so")
    func npmOutdatednessReadsTheSnapshotFlag() {
        let outdated = InstalledFixture.receipt(
            .npm, "typescript", tap: nil, outdatedTo: "5.7.0"
        )
        let current = InstalledFixture.receipt(.npm, "corepack", tap: nil)

        #expect(outdated.snapshotOutdated)
        #expect(outdated.isOutdated)
        #expect(current.isOutdated == false)
    }

    @Test("The cask auto-update exclusion never narrows an npm entry")
    func npmIgnoresTheCaskRule() {
        // `declaresAutoUpdates` is a cask member. An npm receipt that somehow
        // carried it must still be outdated, because the exclusion exists for
        // apps that update themselves and no npm global does.
        let npm = InstalledFixture.receipt(
            .npm, "typescript", tap: nil, outdatedTo: "5.7.0", declaresAutoUpdates: true
        )
        let cask = InstalledFixture.receipt(
            .cask, "iterm2", outdatedTo: "3.6.0", declaresAutoUpdates: true
        )

        #expect(npm.isOutdated)
        #expect(cask.isOutdated == false)
    }

    @Test("Rows sharing a name order formula, then cask, then npm")
    func rankOrderPutsNpmLast() {
        let inventory = InstalledInventory(packages: [
            InstalledFixture.receipt(.npm, "typescript", tap: nil),
            InstalledFixture.receipt(.cask, "typescript"),
            InstalledFixture.receipt(.formula, "typescript")
        ])

        #expect(inventory.packages.map(\.kind) == [.formula, .cask, .npm])
    }

    @Test("Name still decides before namespace")
    func nameOrdersBeforeKind() {
        let inventory = InstalledInventory(packages: [
            InstalledFixture.receipt(.npm, "aaa", tap: nil),
            InstalledFixture.receipt(.formula, "zzz")
        ])

        #expect(inventory.packages.map(\.name) == ["aaa", "zzz"])
    }

    @Test("Ordering stays a strict weak ordering across all three kinds")
    func orderingIsTotal() {
        let names = ["alpha", "beta"]
        let kinds: [PackageKind] = [.formula, .cask, .npm]
        let built = names.flatMap { name in
            kinds.map { InstalledFixture.receipt($0, name, tap: nil) }
        }

        let forward = InstalledInventory(packages: built).packages.map(\.id)
        let reversed = InstalledInventory(packages: built.reversed()).packages.map(\.id)

        #expect(forward == reversed)
        #expect(forward.count == 6)
    }

    @Test("An npm detail projection shows one version row and no keg or link state")
    func npmDetailHasNoKegOrLinkState() {
        let package = InstalledFixture.receipt(
            .npm, "typescript", tap: nil, kegVersions: ["5.6.2"], outdatedTo: "5.7.0"
        )

        let detail = InstalledDetailProjection(package)

        #expect(detail.kindState == .npm(.init(installedVersion: "5.6.2")))
        #expect(detail.installStateFacts.map(\.label) == ["Version"])
        #expect(detail.installStateFacts.map(\.value) == ["5.6.2"])
        // No tap, so no origin row, and nothing borrowed from the formula or
        // cask branches: no link state, no other-versions count, no pin.
        #expect(detail.tapOfOrigin == nil)
    }

    @Test("A brew command cannot be built naming an npm package")
    func packageTargetRejectsNpm() {
        // The npm arm of `MutationCommand.vector` is a `preconditionFailure`, and
        // this is what makes it unreachable rather than merely unvisited: the
        // only way to reach `vector` is through a `PackageTarget`, and no npm
        // identity produces one. Failing construction makes the affordance
        // *unavailable* instead of producing brew argv that names an npm
        // package (design D3).
        #expect(PackageTarget(PackageID(kind: .npm, name: "typescript")) == nil)
        #expect(PackageTarget(kind: .npm, name: "typescript") == nil)
        #expect(PackageTarget(PackageID(kind: .formula, name: "wget")) != nil)
        #expect(PackageTarget(PackageID(kind: .cask, name: "iterm2")) != nil)
    }

    @Test("Neither kind wrapper admits an npm identity either")
    func kindWrappersRejectNpm() {
        #expect(FormulaID(PackageID(kind: .npm, name: "typescript")) == nil)
        #expect(CaskID(PackageID(kind: .npm, name: "typescript")) == nil)
    }

    @Test("An npm entry names its own type rather than falling through to cask")
    func npmDetailNamesItsType() {
        let npm = InstalledDetailProjection(InstalledFixture.receipt(.npm, "typescript", tap: nil))
        let cask = InstalledDetailProjection(InstalledFixture.receipt(.cask, "iterm2"))
        let formula = InstalledDetailProjection(InstalledFixture.receipt(.formula, "wget"))

        #expect(npm.identity.first?.value == "npm package")
        #expect(cask.identity.first?.value == "Cask (GUI app)")
        #expect(formula.identity.first?.value == "Formula (CLI)")
    }
}
