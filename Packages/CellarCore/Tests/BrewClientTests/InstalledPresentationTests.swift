import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// One line per failure, so a view never has to inspect acquisition internals
/// to say what went wrong — the same split `CatalogPresentation` already makes.
@Suite("Installed presentation")
struct InstalledPresentationTests {
    @Test("Every acquisition failure has its own sentence")
    func everyErrorHasItsOwnSentence() {
        let descriptions = [
            InstalledInventoryError.brewUnavailable,
            .commandFailed(status: 1, message: "Error: locked"),
            .malformedPayload,
            .cancelled
        ].map(\.shortDescription)

        #expect(Set(descriptions).count == 4)
        #expect(descriptions.allSatisfy { !$0.isEmpty })
    }

    /// brew's own words when it has any: a wrapped "command failed" tells the
    /// user nothing they can act on.
    @Test("A command failure prefers brew's message over its status")
    func commandFailurePrefersBrewsOwnMessage() {
        let withMessage = InstalledInventoryError.commandFailed(
            status: 1, message: "Error: Another active Homebrew process is already running."
        )
        let silent = InstalledInventoryError.commandFailed(status: 77, message: "")

        #expect(withMessage.shortDescription.contains("Another active Homebrew process"))
        #expect(silent.shortDescription.contains("77"))
    }

    @Test("Every rejection reason has its own sentence")
    func everyRejectionReasonHasItsOwnSentence() {
        let url = URL(fileURLWithPath: "/Users/tester/brew")
        let descriptions = [
            BrewValidationError.notExecutable(url),
            .notHomebrew(url, output: "git version 2.4.0"),
            .versionTooOld(
                BrewVersion(major: 3, minor: 6, patch: 21),
                minimum: BrewVersion(major: 4, minor: 0, patch: 0)
            ),
            .probeFailed(url, message: "the probe never answered")
        ].map(\.shortDescription)

        #expect(Set(descriptions).count == 4)
        #expect(descriptions.allSatisfy { !$0.isEmpty })
    }

    @Test("A version that is too old names both versions")
    func versionTooOldNamesBothVersions() {
        let reason = BrewValidationError.versionTooOld(
            BrewVersion(major: 3, minor: 6, patch: 21),
            minimum: BrewVersion(major: 4, minor: 0, patch: 0)
        )

        #expect(reason.shortDescription.contains("3.6.21"))
        #expect(reason.shortDescription.contains("4.0.0"))
    }

    @Test("Absence guidance names what is wrong, not just that something is")
    func absenceGuidanceNamesTheProblem() {
        let url = URL(fileURLWithPath: "/Users/tester/brew")

        #expect(InstalledAbsence.notInstalled(.standard).title == "Homebrew is not installed")
        #expect(
            InstalledAbsence.configuredPathRejected(url, .notExecutable(url))
                .explanation.contains("/Users/tester/brew")
        )
        #expect(
            InstalledAbsence.configuredPathMissing(url).explanation.contains("/Users/tester/brew")
        )
        // Three distinct situations, three distinct titles.
        let titles = [
            InstalledAbsence.notInstalled(.standard),
            .configuredPathRejected(url, .notExecutable(url)),
            .configuredPathMissing(url)
        ].map(\.title)
        #expect(Set(titles).count == 3)
    }
}
