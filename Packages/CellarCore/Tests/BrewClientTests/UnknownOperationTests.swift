import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// What the client makes of an identity the execution layer does not know.
///
/// Its own suite rather than another case in `ClassificationTests`: that struct
/// is already at the project's `type_body_length` limit, and this is a different
/// question anyway — not "what does brew's prose mean" but "what does *no
/// process at all* mean".
@Suite("Unknown-operation classification")
struct UnknownOperationTests {
    /// The execution layer answers an identity it does not know with a typed
    /// unknown result rather than a fabricated success. Classification carries
    /// that through by mapping it to the **existing** `.launchFailed`, whose doc
    /// already reads "the process never started": no new outcome case, and no
    /// sentence anywhere changes (design D8).
    @Test("An unknown operation classifies as launch failed, not as succeeded")
    func anUnknownOperationClassifiesAsLaunchFailedNotSucceeded() {
        let outcome = MutationOutcome.classify(exit: .unknownOperation, fault: nil, log: [])

        #expect(outcome == .launchFailed)
        #expect(outcome.isFailure)
        #expect(outcome.isSuccess == false, "an unknown identity was reported as a success")
        #expect(outcome != .failed(status: -1), "the unknown sentinel status was shown to the user")
        #expect(outcome.summaryLabel == "Could not start")
        // A terminal outcome like any other, so it owes the same re-snapshot —
        // and, through the single `finish` funnel, the same one history entry
        // (operation-activity; asserted end to end by
        // `aSubmitWithNoRunnerRecordsExactlyOneHistoryEntry`).
        #expect(outcome.forcesReSnapshot)
    }

    /// The structural fact wins over prose, like every other one: an unknown
    /// identity carrying brew's lock text is still a launch failure, not busy.
    @Test("Subprocess prose cannot reclassify an unknown operation")
    func subprocessProseCannotReclassifyAnUnknownOperation() {
        let lock = [
            "Error: A `brew uninstall hello` process has already locked "
                + "/opt/homebrew/Cellar/hello.",
            "Please wait for it to finish or terminate it to continue."
        ]
        let log = lock.enumerated().map { LogLine(stream: .stderr, text: $1, sequence: $0) }

        let outcome = MutationOutcome.classify(exit: .unknownOperation, fault: nil, log: log)

        #expect(outcome == .launchFailed, "an unknown identity was reclassified by subprocess prose")
        #expect(outcome != .busy)
    }
}
