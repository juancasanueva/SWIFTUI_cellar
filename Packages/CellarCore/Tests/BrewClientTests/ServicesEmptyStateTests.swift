import BrewProcess
import Foundation
import Testing

@testable import BrewClient

/// Why the services list is empty — which, exactly as for the installed list,
/// is never the same reason twice.
///
/// `ServicesLoadState` has five cases and the surface has one empty slot, so
/// something must map one onto the other. Doing that mapping in the view with
/// `if let absence` collapses `idle`, `loading` and `failed` into a single
/// affirmative sentence — "Homebrew is not managing any background services on
/// this Mac" — which is a confident factual claim, and false in three of those
/// states. `InstalledEmptyState` already gets this right by switching over all
/// five; this projection is the same rule, hoisted to where `swift test` can
/// prove it rather than where only a human eye can.
@Suite("Services empty state")
struct ServicesEmptyStateTests {
    private static let everyState: [ServicesLoadState] = [
        .idle,
        .loading,
        .loaded,
        .brewAbsent(.notInstalled(.standard)),
        .failed(.brewUnavailable),
        .failed(.commandFailed(status: 1, message: "Error: brew is locked")),
        .failed(.malformedPayload),
        .failed(.cancelled)
    ]

    // MARK: - The three states that are not an affirmative absence

    @Test("A load that has not answered yet says so, and does not claim there are no services")
    func anUnansweredLoadDoesNotClaimThereAreNoServices() {
        for state in [ServicesLoadState.idle, .loading] {
            let empty = state.emptyState

            #expect(empty == .reading, "\(state)")
            #expect(empty.title == "Reading services", "\(state)")
            #expect(
                empty.message.contains("not managing") == false,
                "\(state) is presented as a confirmed absence before brew has answered"
            )
        }
    }

    @Test("A failed probe reports the failure and never an absence")
    func aFailedProbeReportsTheFailure() {
        let failures: [ServicesError] = [
            .brewUnavailable,
            .commandFailed(status: 1, message: "Error: brew is locked"),
            .malformedPayload,
            .cancelled
        ]

        for error in failures {
            let empty = ServicesLoadState.failed(error).emptyState

            #expect(empty == .failed(error.shortDescription), "\(error)")
            #expect(empty.title == "Could not read services", "\(error)")
            #expect(
                empty.message == error.shortDescription,
                "the reason the probe failed is discarded instead of shown"
            )
            #expect(empty.message.isEmpty == false, "\(error)")
        }
    }

    /// brew's own words when it produced any: "the command failed" tells the
    /// user nothing they can act on. The same rule `InstalledInventoryError`
    /// already follows.
    @Test("A non-zero exit shows brew's own stderr, and its status when brew said nothing")
    func aNonZeroExitShowsBrewsOwnWords() {
        #expect(
            ServicesError.commandFailed(status: 1, message: "Error: brew is locked")
                .shortDescription == "Error: brew is locked"
        )
        #expect(
            ServicesError.commandFailed(status: 2, message: "").shortDescription
                .contains("2")
        )
    }

    // MARK: - The two states that are

    @Test("An answered, genuinely empty list is the only state that claims there are no services")
    func onlyAnAnsweredEmptyListClaimsThereAreNone() {
        let empty = ServicesLoadState.loaded.emptyState

        #expect(empty == .nothingManaged)
        #expect(empty.title == "No services")
        #expect(empty.message == "Homebrew is not managing any background services on this Mac.")

        let claiming = Self.everyState.filter { $0.emptyState == .nothingManaged }
        #expect(claiming.count == 1, "\(claiming.count) states claim there are no services")
    }

    /// Absence stays guidance, not an error state (SM11): the wording is
    /// `InstalledAbsence`'s own, so the services surface says exactly what the
    /// rest of the app says.
    @Test("Absent brew stays read-only guidance carrying its own words")
    func absentBrewStaysGuidance() {
        let absence = InstalledAbsence.notInstalled(.standard)
        let empty = ServicesLoadState.brewAbsent(absence).emptyState

        #expect(empty == .brewAbsent(absence))
        #expect(empty.title == absence.title)
        #expect(empty.message == absence.explanation)
        #expect(empty.title != "Could not read services", "guidance is presented as a failure")
    }

    // MARK: - The mapping is total and loses nothing

    @Test("Every load state maps to an empty state, and no two unrelated states share one")
    func theMappingIsTotalAndDoesNotCollapseUnrelatedStates() {
        #expect(Self.everyState.count == 8)

        for state in Self.everyState {
            let empty = state.emptyState
            #expect(empty.title.isEmpty == false, "\(state) has no headline")
            #expect(empty.message.isEmpty == false, "\(state) has no explanation")
        }

        // idle and loading legitimately share one; nothing else does.
        #expect(Set(Self.everyState.map(\.emptyState.title)).count == 4)
    }
}
