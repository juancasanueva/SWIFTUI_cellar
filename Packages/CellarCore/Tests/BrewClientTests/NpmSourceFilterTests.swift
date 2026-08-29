import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The Source dimension, the row tag, and the per-source updates summary.
///
/// All three are `CellarCore` projections: the app target renders a picker, a
/// pill and a sentence, and decides none of them. The rule with the most at
/// stake is the summary's — an npm that was never checked, or whose check
/// failed, must never be summarised as up to date, because that is the one
/// sentence a user acts on by doing nothing.
@Suite("npm source filter, tag and summary")
struct NpmSourceFilterTests {
    private static func inventory() -> InstalledInventory {
        InstalledInventory(packages: [
            InstalledFixture.receipt(.formula, "wget"),
            InstalledFixture.receipt(.cask, "iterm2"),
            InstalledFixture.receipt(.npm, "typescript", tap: nil),
        ])
    }

    private static func browse(
        _ source: NpmSourceAvailability = .available
    ) -> InstalledBrowse {
        InstalledBrowse(inventory: inventory(), isAvailable: true, npmSource: source)
    }

    // MARK: - The Source dimension

    @Test("The npm source narrows to npm entries, and Homebrew to the other two")
    func sourceFilterNarrows() {
        let browse = Self.browse()

        #expect(browse.entries(source: .npm).map(\.name) == ["typescript"])
        #expect(browse.entries(source: .homebrew).map(\.name) == ["iterm2", "wget"])
        #expect(browse.entries(source: nil).map(\.name) == ["iterm2", "typescript", "wget"])
    }

    @Test("The source control is unavailable with a typed reason and filters nothing")
    func unavailableSourceControlIsInert() {
        for (availability, reason) in [
            (NpmSourceAvailability.disabled, NpmSourceUnavailableReason.disabled),
            (.absent, .absent),
            (.invalid, .invalid),
        ] {
            let browse = Self.browse(availability)

            #expect(browse.isSourceFilterEnabled == false)
            #expect(browse.sourceUnavailableReason == reason)
            // Inert, not merely disabled: asking for npm gives the same rows as
            // asking for nothing, so a stale selection cannot empty the list.
            #expect(browse.entries(source: .npm).map(\.name) == ["iterm2", "typescript", "wget"])
            #expect(browse.entries(source: .homebrew).map(\.name)
                == ["iterm2", "typescript", "wget"])
        }
    }

    @Test("An available source control has no unavailable reason")
    func availableControlHasNoReason() {
        #expect(Self.browse().isSourceFilterEnabled)
        #expect(Self.browse().sourceUnavailableReason == nil)
    }

    @Test("The source dimension composes with the dependency toggle")
    func sourceComposesWithDependencies() {
        let inventory = InstalledInventory(packages: [
            InstalledFixture.receipt(.formula, "wget", onRequest: false),
            InstalledFixture.receipt(.npm, "typescript", tap: nil),
        ])
        let browse = InstalledBrowse(
            inventory: inventory, isAvailable: true, npmSource: .available
        )

        #expect(browse.entries(source: nil, includingDependencies: false).map(\.name)
            == ["typescript"])
        #expect(browse.entries(source: nil, includingDependencies: true).map(\.name)
            == ["typescript", "wget"])
        #expect(browse.entries(source: .homebrew, includingDependencies: true).map(\.name)
            == ["wget"])
        #expect(browse.entries(source: .homebrew, includingDependencies: false).isEmpty)
    }

    // MARK: - The tag

    @Test("The tag follows kind and nothing else")
    func tagFollowsKind() {
        #expect(PackageKindTag(kind: .formula) == nil)
        #expect(PackageKindTag(kind: .cask) == .cask)
        #expect(PackageKindTag(kind: .npm) == .npm)
        #expect(PackageKindTag.cask.label == "CASK")
        #expect(PackageKindTag.npm.label == "NPM")
    }

    // MARK: - The updates summary

    @Test("Brew clean and npm offline is not up to date")
    func brewCleanAndNpmOfflineIsNotUpToDate() {
        let summary = InstalledUpdatesSummary(
            browse: Self.browse(),
            metadata: nil,
            npmFreshness: .failed(.networkUnavailable)
        )

        #expect(summary.homebrewCount == 0)
        #expect(summary.npm?.count == 0)
        #expect(summary.npm?.freshness == .failed(.networkUnavailable))
        #expect(summary.isUpToDate == false)
        #expect(summary.total == 0)
    }

    @Test("Brew clean and npm not checked is not up to date either")
    func notCheckedIsNotUpToDate() {
        let summary = InstalledUpdatesSummary(
            browse: Self.browse(),
            metadata: nil,
            npmFreshness: .notChecked(.notYetChecked)
        )

        #expect(summary.isUpToDate == false)
        #expect(summary.npm?.freshness == .notChecked(.notYetChecked))
    }

    @Test("Both sources fresh and clean is up to date")
    func bothFreshAndCleanIsUpToDate() {
        let summary = InstalledUpdatesSummary(
            browse: Self.browse(),
            metadata: nil,
            npmFreshness: .fresh([:], at: Date(timeIntervalSince1970: 0))
        )

        #expect(summary.isUpToDate)
        #expect(summary.total == 0)
    }

    @Test("The summary counts each source separately and totals to the one projection")
    func perSourceCountsTotalToTheProjection() {
        let inventory = InstalledInventory(packages: [
            InstalledFixture.receipt(.formula, "wget", outdatedTo: "2.0.0"),
            InstalledFixture.receipt(.cask, "iterm2", outdatedTo: "3.6.0"),
            InstalledFixture.receipt(.npm, "typescript", tap: nil, outdatedTo: "5.7.0"),
        ])
        let browse = InstalledBrowse(
            inventory: inventory, isAvailable: true, npmSource: .available
        )
        let summary = InstalledUpdatesSummary(
            browse: browse,
            metadata: nil,
            npmFreshness: .fresh(
                ["typescript": NpmOutdatedRecord(current: "1.0.0", wanted: nil, latest: "5.7.0")],
                at: Date(timeIntervalSince1970: 0)
            )
        )

        #expect(summary.homebrewCount == 2)
        #expect(summary.npm?.count == 1)
        #expect(summary.total == 3)
        #expect(summary.total == browse.outdatedCount(metadata: nil))
        #expect(summary.isUpToDate == false)
    }

    @Test("npm off omits npm from the summary entirely")
    func npmOffOmitsNpm() {
        let inventory = InstalledInventory(packages: [
            InstalledFixture.receipt(.formula, "wget", outdatedTo: "2.0.0"),
            InstalledFixture.receipt(.cask, "iterm2", outdatedTo: "3.6.0"),
        ])
        let browse = InstalledBrowse(
            inventory: inventory, isAvailable: true, npmSource: .disabled
        )
        let summary = InstalledUpdatesSummary(
            browse: browse, metadata: nil, npmFreshness: .notChecked(.notYetChecked)
        )

        // Not "npm: 0" and not "npm: not checked" — no npm component at all.
        #expect(summary.npm == nil)
        #expect(summary.homebrewCount == 2)
        #expect(summary.total == 2)
        #expect(summary.total == browse.outdatedCount(metadata: nil))
    }

    @Test("With npm off and nothing outdated the summary is plainly up to date")
    func npmOffAndCleanIsUpToDate() {
        let browse = InstalledBrowse(
            inventory: InstalledInventory(packages: [InstalledFixture.receipt(.formula, "wget")]),
            isAvailable: true,
            npmSource: .disabled
        )
        let summary = InstalledUpdatesSummary(
            browse: browse, metadata: nil, npmFreshness: .failed(.networkUnavailable)
        )

        // The freshness is ignored outright when the source is off: it describes
        // a check that has no business running.
        #expect(summary.npm == nil)
        #expect(summary.isUpToDate)
    }

    @Test("A snoozed npm package leaves the npm count and the outdated set")
    func snoozedNpmPackageLeavesTheCount() {
        let typescript = PackageID(kind: .npm, name: "typescript")
        let corepack = PackageID(kind: .npm, name: "corepack")
        let inventory = InstalledInventory(packages: [
            InstalledFixture.receipt(.npm, "typescript", tap: nil, outdatedTo: "5.7.0"),
            InstalledFixture.receipt(.npm, "corepack", tap: nil, outdatedTo: "0.31.0"),
        ])
        let browse = InstalledBrowse(
            inventory: inventory, isAvailable: true, npmSource: .available
        )
        let metadata: MetadataLookup = { id in
            id == typescript ? PackageMetadata(snoozedVersion: "5.7.0") : nil
        }
        let summary = InstalledUpdatesSummary(
            browse: browse,
            metadata: metadata,
            npmFreshness: .fresh([:], at: Date(timeIntervalSince1970: 0))
        )

        #expect(browse.outdatedIDs(metadata: metadata) == [corepack])
        #expect(summary.npm?.count == 1)
        #expect(summary.total == 1)
    }
}
