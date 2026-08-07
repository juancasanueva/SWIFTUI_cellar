import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The services submit path, and the guard in front of it (design D6 —
/// service-management SM4, SM10, SM11, package-mutation PM7).
///
/// The guard is **services-scoped and deliberately narrow**. `brew-execution`
/// permits duplicate submissions of the same command in general and
/// distinguishes them by identity; the general dedup rule (M2-2 follow-up 7)
/// stays deferred. What is closed here is one specific harm: a double-clicked
/// row queueing two contradictory operations against one service.
@MainActor
@Suite("Service submission", .timeLimit(.minutes(1)))
struct ServiceSubmissionTests {
    private static func target(_ name: String) throws -> ServiceTarget {
        try #require(ServiceTarget(name: name))
    }

    // MARK: - SM10 sc1–sc3 — the duplicate-submit guard

    @Test("A second operation for the same service is refused while one is in flight")
    func aSecondOperationForTheSameServiceIsRefusedWhileOneIsInFlight() async throws {
        let harness = CenterHarness()
        let atuin = try Self.target("atuin")

        let first = harness.center.submit(service: .start(atuin))
        await harness.launcher.waitForLaunches(atLeast: 1)
        #expect(first.isTerminal == false, "the first operation ended, so nothing was in flight")

        // The contradictory second click.
        let second = harness.center.submit(service: .stop(atuin))
        await harness.settle()

        // Same item back, nothing enqueued, nothing spawned.
        #expect(second === first, "a second operation was enqueued for a service already in flight")
        #expect(harness.center.items.count == 1)
        #expect(harness.launcher.launchCount == 1, "a process was spawned for the refused submission")
        #expect(
            harness.center.items.contains { $0.arguments == ["services", "stop", "atuin"] } == false,
            "a contradictory stop was queued behind a start"
        )

        try await harness.finish(call: 0)
    }

    @Test("A different service is not blocked")
    func aDifferentServiceIsNotBlocked() async throws {
        let harness = CenterHarness()

        let atuin = harness.center.submit(service: .start(try Self.target("atuin")))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let postgres = harness.center.submit(service: .start(try Self.target("postgresql")))
        await harness.settle()

        #expect(postgres !== atuin)
        #expect(harness.center.items.count == 2)
        #expect(harness.center.items.map(\.arguments) == [
            ["services", "start", "atuin"],
            ["services", "start", "postgresql"]
        ])

        try await harness.finish(call: 0)
        try await harness.finish(call: 1)
    }

    /// Released at the terminal outcome — **all three of them**, because a guard
    /// that only released on success would strand a service after one failure.
    @Test(
        "The guard is released at the terminal outcome",
        arguments: [TerminalKind.succeeded, .failed, .cancelled]
    )
    func theGuardIsReleasedAtTheTerminalOutcome(kind: TerminalKind) async throws {
        let harness = CenterHarness(honoursInterrupt: false)
        let atuin = try Self.target("atuin")

        let first = harness.center.submit(service: .start(atuin))
        await harness.launcher.waitForLaunches(atLeast: 1)

        switch kind {
        case .succeeded:
            try await harness.finish(call: 0)
        case .failed:
            try await harness.finish(call: 0, status: 1)
        case .cancelled:
            harness.center.cancel(first)
            let process = harness.launcher.launchedProcesses[0]
            await harness.poll { process.deliveredSignals.isEmpty == false }
            process.terminate(with: BrewExit(status: 130, reason: .cancelled(signal: SIGINT)))
            await harness.poll { first.isTerminal }
            await harness.settle()
        }

        #expect(first.isTerminal, "the operation never reached a terminal outcome")
        #expect(first.outcome == kind.outcome)

        // And now a stop enqueues normally.
        let second = harness.center.submit(service: .stop(atuin))
        await harness.settle()

        #expect(second !== first, "the guard was not released after \(kind)")
        #expect(harness.center.items.count == 2)
        #expect(second.arguments == ["services", "stop", "atuin"])
        try await harness.finish(call: 1)
    }

    enum TerminalKind: Sendable, CustomStringConvertible {
        case succeeded
        case failed
        case cancelled

        var outcome: MutationOutcome {
            switch self {
            case .succeeded: .succeeded
            case .failed: .failed(status: 1)
            case .cancelled: .cancelled
            }
        }

        var description: String {
            switch self {
            case .succeeded: "a successful terminal"
            case .failed: "a failed terminal"
            case .cancelled: "a cancelled terminal"
            }
        }
    }

    // MARK: - SM4 sc4 — one operation per service, in order

    /// The M2 fan-out ruling, applied to the second family: **no `--all`**. Each
    /// service gets its own queue item, log, copy-command, cancel and terminal
    /// outcome, so a mid-batch failure attributes to exactly one service.
    @Test("Acting on several services enqueues one operation each, in order")
    func actingOnSeveralServicesEnqueuesOneOperationEachInOrder() async throws {
        let harness = CenterHarness()
        let names = ["atuin", "postgresql", "redis"]
        let commands = try names.map { ServiceCommand.stop(try Self.target($0)) }

        let items = harness.center.submit(services: commands)
        await harness.settle()

        #expect(items.count == 3)
        #expect(items.map(\.arguments) == [
            ["services", "stop", "atuin"],
            ["services", "stop", "postgresql"],
            ["services", "stop", "redis"]
        ])
        // In that order, and each its own operation.
        #expect(harness.center.items.map(\.id) == items.map(\.id))
        #expect(Set(items.map(\.id)).count == 3)
        for item in items {
            #expect(item.arguments.contains("--all") == false)
        }

        for index in 0..<3 { try await harness.finish(call: index) }
    }

    // MARK: - SM11 sc2, PM7 sc4 — brew absent

    @Test(
        "Absent brew spawns nothing for any of the four verbs",
        arguments: [DetachedKind.neverAttached, .invalidPath]
    )
    func absentBrewSpawnsNothingForAnyOfTheFourVerbs(kind: DetachedKind) async throws {
        let harness = CenterHarness(attached: false)
        if case .invalidPath = kind {
            // Pointed at something, then pointed away again — the shape a
            // rejected configured path produces.
            harness.center.attach(installation: TestInstallation.appleSilicon)
            harness.center.attach(installation: nil)
        }

        let atuin = try Self.target("atuin")
        let items = ServiceCommand.allVerbs(for: atuin).map { harness.center.submit(service: $0) }
        await harness.settle()

        // Nothing spawned, nothing thrown, and each reported rather than silent.
        #expect(harness.launcher.launchCount == 0, "a process was spawned with no brew")
        #expect(items.count == 4)
        for item in items {
            #expect(item.isTerminal, "an unavailable submission was left pending forever")
            #expect(item.outcome == .launchFailed)
        }

        // The affordance reports itself unavailable, with the reason available
        // as read-only guidance rather than as an error.
        #expect(harness.center.isAvailable == false)
        let guidance = try #require(harness.center.unavailableGuidance)
        #expect(guidance.isEmpty == false)
        #expect(guidance.lowercased().contains("homebrew"))

        // And each of the four still recorded its entry (OA6).
        #expect(harness.recorder.drafts.count == 4)
    }

    enum DetachedKind: Sendable, CustomStringConvertible {
        case neverAttached
        case invalidPath

        var description: String {
            switch self {
            case .neverAttached: "detection reported absent"
            case .invalidPath: "an invalid configured path"
            }
        }
    }

    // MARK: - SM4 sc5, II13 sc4 — the installed bulk vocabulary is untouched

    /// **Load-bearing for `installed-inventory` II13**, which proves exhaustively
    /// over `allCases` which bulk verbs exist. A services multi-select — if one
    /// ever ships — must be its own type over its own entity; adding a case here
    /// would break that scenario and silently offer "start" over a package
    /// selection.
    ///
    /// **Rewritten, not deleted** (m5-health). Only the two vocabulary lines
    /// changed, from two cases to four: the package bulk vocabulary widened to
    /// include pin and unpin by maintainer ruling. Everything below is untouched,
    /// because this is a **services** test and its point is unaffected by that
    /// widening — SM4 sc5 asks whether a *service* verb leaked into the package
    /// vocabulary, not whether that vocabulary is frozen. That question survives
    /// the widening intact, and it is the reason this file asserts anything about
    /// `BulkSelection` at all.
    @Test("The installed bulk vocabulary contains no service verb")
    func theInstalledBulkVocabularyIsUnchanged() {
        #expect(BulkSelection.Action.allCases == [.upgrade, .uninstall, .pin, .unpin])
        #expect(BulkSelection.Action.allCases.count == 4)

        let verbs = ServiceCommand.allVerbs(for: ServiceTarget(name: "atuin")!).map(\.verb)
        for action in BulkSelection.Action.allCases {
            #expect(verbs.contains("\(action)") == false, "a service verb entered the bulk vocabulary")
        }
        // And no services bulk affordance exists to add one to.
        #expect(ServiceRowControl.allCases.count == 5)
    }
}
