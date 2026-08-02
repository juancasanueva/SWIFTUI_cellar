import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The centre's session-long enumeration against the execution layer's now
/// bounded records (operation-activity OA1 sc5, design D6).
///
/// Its own suite rather than another test in `OperationCenterProjectionTests`,
/// which is already at SwiftLint's `type_body_length` limit — and this is a
/// distinct claim: the projection is correct *and* it outlives the record it
/// was projected from.
@MainActor
@Suite("Operation center retention", .timeLimit(.minutes(1)))
struct OperationCenterRetentionTests {
    // MARK: - Retention is the execution layer's, not the session's (OA1 sc5)

    /// `brew-execution` now retires terminal, fully drained records (design D6).
    /// The centre's session-long enumeration must not depend on that record: it
    /// must keep the item's identity, its argv and its terminal outcome once the
    /// execution layer has stopped reporting the operation at all.
    ///
    /// `apply(_:)` writes a phase only for ids the incoming snapshot carries, so
    /// a snapshot that omits a retired operation leaves its item alone. That
    /// tolerance was incidental in M2-2; here it becomes load-bearing.
    @Test("A terminal item survives its execution record no longer being reported")
    func terminalItemsSurviveRecordRetirement() async throws {
        let harness = CenterHarness()

        let item = harness.center.submit(.install(CenterHarness.iterm))
        await harness.finish(call: 0)
        #expect(item.outcome == .succeeded)

        // Settling drops the item's own handle, so the runner may retire the
        // record: nothing above the execution layer holds it any more (D6).
        #expect(item.operation == nil, "a settled item still held its BrewOperation")

        // Repointing gives the centre a runner whose queue snapshots never
        // mention the first operation — the same shape a retired record has.
        harness.center.attach(installation: TestInstallation.intel)
        let later = harness.center.submit(.install(CenterHarness.git))
        await harness.finish(call: 1)
        #expect(later.outcome == .succeeded)
        await harness.settle()

        let survivor = try #require(harness.center.items.first { $0.id == item.id })
        #expect(survivor.arguments == ["install", "--cask", "iterm2"])
        #expect(survivor.outcome == .succeeded)
        #expect(survivor.isTerminal)
        #expect(survivor.queuePhase.isTerminal, "a retired record reset the item's phase")
        #expect(harness.center.items.map(\.id) == [item.id, later.id])
    }
}
