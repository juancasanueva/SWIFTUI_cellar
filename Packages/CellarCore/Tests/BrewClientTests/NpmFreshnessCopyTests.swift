import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The sentences every count-bearing surface reads, and the one sentence none of
/// them may say on an unchecked npm.
///
/// Unit 1 proved the *boolean*: `isUpToDate` is false when npm was not checked.
/// A boolean is not what a user reads, though, and three surfaces — the menu
/// bar, Health and Home — each have to turn it into words. If each of them wrote
/// its own sentence, one of them would eventually say "up to date" over a
/// `notChecked`, and the whole point of the tri-state would be lost in the copy
/// layer. So the words live here, beside the state, in the `swift test` inner
/// loop (`installed-inventory`: an unchecked npm never reads as up to date;
/// `npm-source`: the three freshness states are distinct copy).
@Suite("npm freshness copy")
struct NpmFreshnessCopyTests {
    private static let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static func browse(
        _ packages: [InstalledPackage],
        npmSource: NpmSourceAvailability = .available
    ) -> InstalledBrowse {
        InstalledBrowse(
            inventory: InstalledInventory(packages: packages),
            isAvailable: true,
            npmSource: npmSource
        )
    }

    // MARK: - The state's own words

    /// A completed check has nothing to disclose: the count already says it.
    @Test("A completed check produces no not-checked copy")
    func freshHasNoNotCheckedCopy() {
        #expect(NpmOutdatedState.fresh([:], at: Self.checkedAt).notCheckedCopy == nil)
        #expect(
            NpmOutdatedState.fresh(
                ["typescript": NpmOutdatedRecord(current: "5.6.0", wanted: nil, latest: "5.7.0")],
                at: Self.checkedAt
            ).notCheckedCopy == nil
        )
    }

    /// Every non-answer names itself, and every one of them carries the same
    /// three words a surface can look for.
    @Test(
        "Every non-answer says npm was not checked and names its reason",
        arguments: [
            (NpmOutdatedState.notChecked(.notYetChecked), "yet"),
            (.notChecked(.cancelled), "cancelled"),
            (.failed(.networkUnavailable), "network"),
            (.failed(.npmUnavailable), "run"),
            (.failed(.malformedPayload), "read"),
            (.failed(.commandFailed(status: 1, message: "boom")), "complete"),
            (.failed(.cancelled), "cancelled"),
        ]
    )
    func everyNonAnswerNamesItself(state: NpmOutdatedState, reason: String) throws {
        let copy = try #require(state.notCheckedCopy, "a non-answer produced no copy")

        #expect(copy.contains("npm not checked"))
        #expect(copy.contains(reason), "\(copy) does not name its reason")
        #expect(copy.localizedCaseInsensitiveContains("up to date") == false)
    }

    /// The offline sentence is the one Health names explicitly, and it must say
    /// *network* rather than leaving the user to guess at "failed".
    @Test("Offline names the network and the registry, and never Homebrew")
    func offlineNamesTheNetwork() throws {
        let copy = try #require(NpmOutdatedState.failed(.networkUnavailable).notCheckedCopy)

        #expect(copy.contains("network"))
        #expect(copy.contains("registry"))
        #expect(copy.localizedCaseInsensitiveContains("homebrew") == false)
        #expect(copy.localizedCaseInsensitiveContains("brew") == false)
    }

    // MARK: - The summary's words

    @Test("Brew clean and npm not checked reports both halves and refuses up to date")
    func brewCleanAndNpmNotCheckedRefusesUpToDate() throws {
        let summary = InstalledUpdatesSummary(
            browse: Self.browse([InstalledFixture.receipt(.formula, "wget")]),
            metadata: nil,
            npmFreshness: .failed(.networkUnavailable)
        )

        #expect(summary.homebrewCount == 0)
        #expect(summary.isUpToDate == false)
        #expect(summary.upToDateCopy == nil, "an unchecked npm was summarised as up to date")

        let npmCopy = try #require(summary.npmNotCheckedCopy)
        #expect(npmCopy.contains("npm not checked"))
        #expect(npmCopy.contains("network"))
    }

    /// Triangulation: the same summary over a *completed* check says the one
    /// sentence the case above forbids, so the refusal above is a decision
    /// rather than a missing implementation.
    @Test("Both sources clean and npm checked is allowed to say up to date")
    func bothCleanAndCheckedMaySayUpToDate() {
        let summary = InstalledUpdatesSummary(
            browse: Self.browse([InstalledFixture.receipt(.formula, "wget")]),
            metadata: nil,
            npmFreshness: .fresh([:], at: Self.checkedAt)
        )

        #expect(summary.isUpToDate)
        #expect(summary.npmNotCheckedCopy == nil)
        #expect(summary.upToDateCopy == InstalledUpdatesSummary.upToDateLabel)
    }

    /// An outdated package is not "up to date" either, and the absence is the
    /// value: a surface never has to decide locally what nothing looks like.
    @Test("Something outdated produces no up-to-date copy at all")
    func somethingOutdatedProducesNoUpToDateCopy() {
        let summary = InstalledUpdatesSummary(
            browse: Self.browse([InstalledFixture.receipt(.formula, "wget", outdatedTo: "2.0.0")]),
            metadata: nil,
            npmFreshness: .fresh([:], at: Self.checkedAt)
        )

        #expect(summary.homebrewCount == 1)
        #expect(summary.upToDateCopy == nil)
        #expect(summary.npmNotCheckedCopy == nil)
    }

    @Test("With the source off there is no npm copy, whatever the freshness says")
    func npmOffProducesNoNpmCopy() {
        for freshness in [
            NpmOutdatedState.notChecked(.notYetChecked),
            .failed(.networkUnavailable),
            .fresh([:], at: Self.checkedAt),
        ] {
            let summary = InstalledUpdatesSummary(
                browse: Self.browse(
                    [InstalledFixture.receipt(.formula, "wget")], npmSource: .disabled
                ),
                metadata: nil,
                npmFreshness: freshness
            )

            #expect(summary.npm == nil)
            #expect(summary.npmNotCheckedCopy == nil, "an off source still produced npm copy")
            #expect(summary.upToDateCopy == InstalledUpdatesSummary.upToDateLabel)
        }
    }
}
