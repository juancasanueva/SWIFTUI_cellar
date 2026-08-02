import CellarTestSupport
import Foundation
import Testing

@testable import BrewProcess

/// What the queue stream publishes, as opposed to what the queue contains.
///
/// Split from `QueueProjectionTests` rather than added to it: that suite was
/// already at SwiftLint's `type_body_length` limit, and publication is its own
/// claim — the projection is correct *and* it is announced once per real
/// transition (brew-execution BE1 sc10, design D6 follow-up 4b).
@Suite("Queue publication", .timeLimit(.minutes(1)))
struct QueuePublicationTests {
    private static func runner(_ launcher: FakeProcessLauncher) -> BrewRunner {
        BrewRunner(installation: .fixture, launcher: launcher)
    }

    private static func install(_ name: String) -> BrewCommand {
        .mutate(["install", "--formula", name])
    }

    private static func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    /// BE1 sc10 — an unchanged phase is not republished (design D6, follow-up
    /// 4b). The consumer is pull-based on purpose: with no equality guard the
    /// `.bufferingNewest(1)` buffer would be holding a *repeat* of the running
    /// snapshot, so the next pull would answer `.running` instead of blocking
    /// until the real terminal transition.
    @Test("Repeated publication of the same phase yields nothing between real transitions")
    func anUnchangedPhaseIsNotRepublished() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        var iterator = runner.queue.makeAsyncIterator()
        let operation = try await runner.start(Self.install("a"))
        await launcher.waitForLaunches(atLeast: 1)

        // A mutation publishes `.pending` before it publishes `.running`, and
        // which of the two the buffer still holds is a scheduling detail.
        var running = try #require(await iterator.next())
        while running.operations.first?.phase != .running {
            running = try #require(await iterator.next())
        }
        #expect(running.operations.map(\.phase) == [.running])

        // Twenty yields of a value that has not changed.
        for _ in 0..<20 { await runner.republish() }
        await Self.settle()

        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))

        let next = try #require(await iterator.next())
        #expect(next.operations.first?.phase.isTerminal == true, "a repeat was published as a change")
        #expect(next.operations.first?.id == operation.id)
        _ = await operation.exit()
    }
}
