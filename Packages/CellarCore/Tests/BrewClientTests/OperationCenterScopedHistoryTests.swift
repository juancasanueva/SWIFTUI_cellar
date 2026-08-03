import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The recorder's side-effect guarantee, restated for an operation that carries
/// **no package identity** and a state domain of its own (installation-history
/// IH7 sc3, operation-activity OA6 sc6).
///
/// Split out of `OperationCenterHistoryTests` for the reason task 17.1 gives —
/// that suite is at SwiftLint's `type_body_length` bound, and the answer is a
/// split, not a suppression.
@MainActor
@Suite("Operation center scoped history", .timeLimit(.minutes(1)))
struct OperationCenterScopedHistoryTests {
    typealias RecorderKind = OperationCenterHistoryTests.RecorderKind

    /// The same guarantee for an operation with **no package identity** and a
    /// domain of its own (IH7 sc3, OA6 sc6).
    ///
    /// Three claims at once, because IH7's amendment is exactly about their
    /// conjunction: the reported outcome is identical to the working-recorder
    /// run, exactly one refresh is forced for each domain the command declared
    /// and none for any it did not, and nothing is thrown into the operation's
    /// path.
    @Test(
        "A failing recorder changes neither the outcome nor the per-domain refresh counts",
        arguments: [RecorderKind.working, .absent, .failing]
    )
    func aFailingRecorderChangesNeitherTheOutcomeNorThePerDomainRefreshCounts(
        kind: RecorderKind
    ) async throws {
        let harness = CenterHarness(history: kind.recorder)
        let services = Counter()
        let installed = Counter()
        let servicesWatcher = Task { [stream = harness.servicesGate.terminals] in
            for await _ in stream { services.increment() }
        }
        let installedWatcher = Task { [stream = harness.gate.terminals] in
            for await _ in stream { installed.increment() }
        }
        await harness.settle()

        let item = harness.center.submit(ProbeMutation())
        await harness.launcher.waitForLaunches(atLeast: 1)
        harness.launcher.launchedProcesses[0].emitStdout("==> Successfully started `atuin`\n")
        await harness.settle()
        try await harness.finish(call: 0)
        await harness.settle()

        // Identical in all three worlds.
        #expect(item.outcome == .succeeded)
        #expect(item.log.map(\.text) == ["==> Successfully started `atuin`"])
        #expect(item.packageID == nil, "a non-package operation was given an identity")
        #expect(
            services.value == 1,
            "\(kind) forced \(services.value) refreshes of the declared domain rather than one"
        )
        #expect(
            installed.value == 0,
            "\(kind) forced \(installed.value) inventory re-snapshots for a command that declared none"
        )
        #expect(harness.servicesGate.isMutating == false)
        #expect(harness.gate.isMutating == false)
        servicesWatcher.cancel()
        installedWatcher.cancel()
    }

}
