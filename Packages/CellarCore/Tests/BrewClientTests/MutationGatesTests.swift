import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// Scoped invalidation: a terminal outcome refreshes what its **command**
/// declared, and nothing else (design D2 — package-mutation PM6,
/// installed-inventory II10, service-management SM8).
///
/// The invariant M2 shipped is preserved exactly and asserted first: a command
/// declaring the installed set still owes exactly one re-snapshot at *every*
/// terminal — success, plain failure, the typed busy failure and cancellation
/// alike. What changes is that the obligation now comes from the command rather
/// than from a constant on the outcome, so a command that cannot change the
/// installed set can decline a probe that could not observe a difference.
///
/// The inventory probe is driven through a **real** `BrewInfoPayloadSource` over
/// a recording launcher, so "no `brew info --installed --json=v2` invocation was
/// recorded" is a claim about the literal argv rather than about a counter that
/// happens to stand in for one.
@MainActor
@Suite("Mutation gates", .timeLimit(.minutes(1)))
struct MutationGatesTests {
    private static let wget = PackageID(kind: .formula, name: "wget")

    /// The whole spine wired the way the app wires it, with two domains.
    private struct Harness {
        let mutations: ControllableProcessLauncher
        /// Everything the inventory refresh spawns. Its specs are the evidence.
        let inventoryLauncher: RecordingProcessLauncher
        let installedGate: InstalledMutationGate
        let servicesGate: InstalledMutationGate
        let installed: InstalledStore
        let clock: TestClock
        let coordinator: InstalledRefreshCoordinator
        let center: OperationCenter
        let recorder: RecordingHistoryRecorder
        /// One tick per services terminal, so the declared domain's refresh is
        /// counted rather than assumed.
        let servicesTerminals: Counter
        /// The coordinator's loop and the terminals watcher, held so a test
        /// ends both together rather than leaving either running past it.
        let loop: Task<Void, Never>
        let watcher: Task<Void, Never>

        /// Every recorded inventory probe, by its literal argv.
        var inventoryProbes: [[String]] {
            inventoryLauncher.specs.map(\.arguments)
        }

        func stop() {
            loop.cancel()
            watcher.cancel()
        }
    }

    private func harness(
        honoursInterrupt: Bool = true,
        history: (any HistoryRecording)? = nil
    ) -> Harness {
        let mutations = ControllableProcessLauncher(honoursInterrupt: honoursInterrupt)
        let inventoryLauncher = RecordingProcessLauncher()
        let installedGate = InstalledMutationGate()
        let servicesGate = InstalledMutationGate()
        let installed = InstalledStore(source: BrewInfoPayloadSource(launcher: inventoryLauncher))
        let clock = TestClock()
        let coordinator = InstalledRefreshCoordinator(
            store: installed,
            mutations: installedGate,
            clock: clock
        )
        let recorder = RecordingHistoryRecorder()
        let center = OperationCenter(
            gates: MutationGates([
                (.installedInventory, installedGate),
                (.services, servicesGate)
            ]),
            history: history ?? recorder,
            launcherFactory: { _ in mutations }
        )
        center.attach(installation: TestInstallation.appleSilicon)

        let terminals = Counter()
        let watcher = Task { [stream = servicesGate.terminals] in
            for await _ in stream { terminals.increment() }
        }
        let loop = Task { await coordinator.run() }

        return Harness(
            mutations: mutations,
            inventoryLauncher: inventoryLauncher,
            installedGate: installedGate,
            servicesGate: servicesGate,
            installed: installed,
            clock: clock,
            coordinator: coordinator,
            center: center,
            recorder: recorder,
            servicesTerminals: terminals,
            loop: loop,
            watcher: watcher
        )
    }

    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    /// Terminates the `index`-th mutation process and lets everything downstream
    /// of it — the gate, the coordinator, the recorder — observe it.
    private func finish(
        _ harness: Harness,
        call index: Int,
        status: Int32 = 0,
        reason: BrewExit.Reason = .exited
    ) async throws {
        await TestPoll.until(harness.mutations.launchCount >= index + 1)
        let process = try #require(
            harness.mutations.launchedProcesses.indices.contains(index)
                ? harness.mutations.launchedProcesses[index]
                : nil,
            "no mutation process was launched for call \(index)"
        )
        process.terminate(with: BrewExit(status: status, reason: reason))
        await settle()
    }

    /// brew's live-probed lock wording, which classifies as the typed busy
    /// failure.
    private static let lockLine =
        "Error: A `brew uninstall wget` process has already locked /opt/homebrew/Cellar/wget.\n"

    // MARK: - PM6 sc1–sc3 — the carried-forward invariant, unchanged

    /// The M2 guarantee, restated over the new mechanism. It must stay green:
    /// every terminal a package mutation can reach still owes exactly one
    /// inventory re-snapshot.
    @Test("A command declaring the installed set refreshes it exactly once at every terminal")
    func aCommandDeclaringTheInstalledSetRefreshesItExactlyOnceAtEveryTerminal() async throws {
        let harness = harness(honoursInterrupt: false)
        defer { harness.stop() }

        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.inventoryLauncher.launchCount
        #expect(baseline == 1, "the baseline refresh did not run, so counting from it proves nothing")

        // 1 — success.
        let succeeded = harness.center.submit(.install(PackageTarget(Self.wget)!))
        try await finish(harness, call: 0)
        #expect(succeeded.outcome == .succeeded)
        #expect(harness.inventoryLauncher.launchCount - baseline == 1)

        // 2 — a plain non-zero exit.
        let failed = harness.center.submit(.install(PackageTarget(Self.wget)!))
        try await finish(harness, call: 1, status: 1)
        #expect(failed.outcome == .failed(status: 1))
        #expect(harness.inventoryLauncher.launchCount - baseline == 2)

        // 3 — the typed busy failure.
        let busy = harness.center.submit(.install(PackageTarget(Self.wget)!))
        await harness.mutations.waitForLaunches(atLeast: 3)
        harness.mutations.launchedProcesses[2].emitStderr(Self.lockLine)
        await settle()
        try await finish(harness, call: 2, status: 1)
        #expect(busy.outcome == .busy)
        #expect(harness.inventoryLauncher.launchCount - baseline == 3)

        // 4 — cancellation.
        let cancelled = harness.center.submit(.install(PackageTarget(Self.wget)!))
        await harness.mutations.waitForLaunches(atLeast: 4)
        harness.center.cancel(cancelled)
        let process = harness.mutations.launchedProcesses[3]
        await TestPoll.until(process.deliveredSignals.isEmpty == false)
        process.terminate(with: BrewExit(status: 130, reason: .cancelled(signal: SIGINT)))
        await settle()
        #expect(cancelled.outcome == .cancelled)
        #expect(harness.inventoryLauncher.launchCount - baseline == 4)

        // Every probe was the inventory probe, and the gate is closed again.
        #expect(harness.inventoryProbes.allSatisfy { $0 == ["info", "--installed", "--json=v2"] })
        #expect(harness.installedGate.isMutating == false)
        // A package mutation declares no services domain, so that gate never
        // fired at all — the mapping is an intersection, not a broadcast.
        #expect(harness.servicesTerminals.value == 0, "a package mutation refreshed services")
    }

    // MARK: - PM6 sc4–sc5, II10 sc8, SM8 — a command that declares another domain

    @Test("A command that does not declare the installed set takes no inventory snapshot")
    func aCommandThatDoesNotDeclareTheInstalledSetTakesNoInventorySnapshot() async throws {
        let harness = harness(honoursInterrupt: false)
        defer { harness.stop() }

        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.inventoryLauncher.launchCount
        #expect(baseline == 1)

        // Success, failure and cancellation, one after another.
        let succeeded = harness.center.submit(ProbeMutation())
        try await finish(harness, call: 0)
        #expect(succeeded.outcome == .succeeded)

        let failed = harness.center.submit(ProbeMutation())
        try await finish(harness, call: 1, status: 1)
        #expect(failed.outcome == .failed(status: 1))

        let cancelled = harness.center.submit(ProbeMutation())
        await harness.mutations.waitForLaunches(atLeast: 3)
        harness.center.cancel(cancelled)
        let process = harness.mutations.launchedProcesses[2]
        await TestPoll.until(process.deliveredSignals.isEmpty == false)
        process.terminate(with: BrewExit(status: 130, reason: .cancelled(signal: SIGINT)))
        await settle()
        #expect(cancelled.outcome == .cancelled)

        // Zero inventory probes across all three terminals — asserted on the
        // literal argv, not on a stand-in counter.
        #expect(
            harness.inventoryLauncher.launchCount == baseline,
            """
            \(harness.inventoryLauncher.launchCount - baseline) inventory probe(s) ran for a \
            command that does not invalidate the installed set
            """
        )
        // Positively anchored: the one probe recorded is the baseline, and it
        // really is the inventory argv — so "no further probe ran" is a claim
        // about a launcher that demonstrably does record this invocation.
        #expect(harness.inventoryProbes == [["info", "--installed", "--json=v2"]])

        // And exactly one refresh of the domain it *did* declare, per terminal.
        #expect(
            harness.servicesTerminals.value == 3,
            "three terminals owed three services refreshes, got \(harness.servicesTerminals.value)"
        )
        #expect(harness.servicesGate.isMutating == false)
        // The installed gate was never even opened, which is what keeps
        // `InstalledChangeObserving` byte-unchanged: suppression falls out of
        // never calling `begin()`, not out of a new flag inside it.
        #expect(harness.installedGate.isMutating == false)
    }

    /// The declaration is read from the **command**, before submission, and is
    /// not derived from how the operation ended (PM6).
    @Test("The invalidation scope is readable before submission and never comes from the outcome")
    func theScopeIsAPropertyOfTheCommandNotOfTheOutcome() throws {
        #expect(MutationCommand.upgradeAll.invalidates == .installedInventory)
        #expect(ProbeMutation().invalidates == .services)

        // The replaced mechanism is gone: nothing on the outcome answers this
        // question any more, so there is no unconditional value to fall back to.
        let source = try Self.source(of: "MutationOutcome.swift")
        #expect(source.contains("forcesReSnapshot") == false, "the outcome still decides invalidation")
        #expect(source.contains("public enum MutationOutcome"), "the scan ran against the wrong file")
    }

    /// The intersection is genuinely an intersection: a command declaring both
    /// domains pays both, and one declaring none still reaches its terminal.
    @Test("Declaring both domains refreshes both, and declaring none still settles")
    func theMappingIsAnIntersection() async throws {
        let harness = harness()
        defer { harness.stop() }

        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.inventoryLauncher.launchCount

        let both = harness.center.submit(
            ProbeMutation(invalidates: [.installedInventory, .services])
        )
        try await finish(harness, call: 0)
        #expect(both.outcome == .succeeded)
        #expect(harness.inventoryLauncher.launchCount - baseline == 1)
        #expect(harness.servicesTerminals.value == 1)

        // A command declaring nothing must still settle, still record, and
        // still report on the same terms (PM6).
        let none = harness.center.submit(ProbeMutation(invalidates: []))
        try await finish(harness, call: 1)
        #expect(none.outcome == .succeeded)
        #expect(harness.inventoryLauncher.launchCount - baseline == 1, "a scopeless command refreshed")
        #expect(harness.servicesTerminals.value == 1)
        #expect(harness.recorder.drafts.count == 2, "a scopeless command skipped its history entry")
    }

    private static func source(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/BrewClient/\(file)"),
            encoding: .utf8
        )
    }
}
