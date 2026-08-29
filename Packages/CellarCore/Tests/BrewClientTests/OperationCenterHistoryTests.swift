import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The one terminal funnel, and the one durable record it owes
/// (operation-activity OA6, installation-history IH1–IH2, IH7, design D7).
///
/// `finish(_:with:)` is already the single, idempotent place a mutation settles
/// and pays the gate exactly once. Hanging the write there is what makes
/// "exactly one entry per terminal outcome" true **by construction** rather than
/// by discipline — so these tests assert the count as hard as they assert the
/// contents.
@MainActor
@Suite("Operation center history", .timeLimit(.minutes(1)))
struct OperationCenterHistoryTests {

    @Test("Tap add untap and force untap each write one null-package exact-argv entry")
    func tapMutationsWriteNamespacedNullPackageHistory() async throws {
        let harness = CenterHarness()
        let tap = try #require(TapName("acme/tools"))
        let commands = [
            try #require(TapCommand.add(tap.rawValue)),
            try #require(TapCommand.untap(tap.rawValue)),
            try #require(TapCommand.forceUntap(evidence: ForceUntapEvidence(
                tap: tap,
                affected: [PackageID(kind: .formula, name: "widget")],
                isComplete: true
            )))
        ]

        for (index, command) in commands.enumerated() {
            harness.center.submit(command)
            try await harness.finish(call: index)
        }

        #expect(harness.recorder.drafts.count == 3)
        #expect(harness.recorder.drafts.map(\.verb) == ["tapAdd", "tapUntap", "tapForceUntap"])
        #expect(harness.recorder.drafts.map(\.argv) == [
            ["tap", "acme/tools"],
            ["untap", "acme/tools"],
            ["untap", "--force", "acme/tools"]
        ])
        #expect(harness.recorder.drafts.allSatisfy { $0.packageID == nil && $0.versions == nil })
    }
    private static func target(_ id: PackageID) throws -> PackageTarget {
        try #require(PackageTarget(id))
    }

    /// brew's own lock wording, live-probed on 6.0.14. The classifier reads it
    /// off stderr, and the persisted outcome is derived from the classifier —
    /// never from the raw bytes.
    private static let lockLine = "Error: wget has already locked the keg.\n"

    // MARK: - OA6 sc1, IH1 sc1 — one complete entry per successful terminal

    @Test("A successful install submits exactly one draft carrying identity, verb, outcome and argv")
    func aSuccessfulInstallSubmitsOneCompleteDraft() async throws {
        let harness = CenterHarness()
        let item = harness.center.submit(.install(try Self.target(CenterHarness.iterm)))
        await harness.settle()

        #expect(harness.recorder.drafts.isEmpty, "a draft was written before the terminal outcome")

        try await harness.finish(call: 0)

        #expect(harness.recorder.drafts.count == 1)
        let draft = try #require(harness.recorder.drafts.first)
        #expect(draft.id == item.id, "the draft is not the item's own identity")
        #expect(draft.packageID == CenterHarness.iterm)
        #expect(draft.packageID?.kind == .cask)
        #expect(draft.verb == "install")
        #expect(draft.outcome == .succeeded)
        #expect(draft.argv == ["install", "--cask", "iterm2"])
        #expect(draft.commandText == "install --cask iterm2")
    }

    // MARK: - OA6 sc2, IH1 sc2 — failure, busy and cancellation each name themselves

    @Test("A failing, a busy and a cancelled mutation each submit one draft naming its own outcome")
    func everyTerminalOutcomeIsRecordedAsItself() async throws {
        let harness = CenterHarness(honoursInterrupt: false)

        let failing = harness.center.submit(.install(try Self.target(CenterHarness.wget)))
        await harness.launcher.waitForLaunches(atLeast: 1)
        try await harness.finish(call: 0, status: 1)

        let busy = harness.center.submit(.install(try Self.target(CenterHarness.git)))
        await harness.launcher.waitForLaunches(atLeast: 2)
        harness.launcher.launchedProcesses[1].emitStderr(Self.lockLine)
        await harness.settle()
        try await harness.finish(call: 1, status: 1)

        let cancelled = harness.center.submit(.install(try Self.target(CenterHarness.iterm)))
        await harness.launcher.waitForLaunches(atLeast: 3)
        harness.center.cancel(cancelled)
        let process = harness.launcher.launchedProcesses[2]
        await harness.poll { process.deliveredSignals.isEmpty == false }
        process.terminate(with: BrewExit(status: 130, reason: .signalled(SIGINT)))
        await harness.poll { cancelled.isTerminal }
        await harness.settle()

        #expect(failing.outcome == .failed(status: 1))
        #expect(busy.outcome == .busy)
        #expect(cancelled.outcome == .cancelled)

        // Exactly one each, and each naming its own outcome rather than a
        // generic one.
        #expect(harness.recorder.drafts.count == 3)
        let byID = Dictionary(
            harness.recorder.drafts.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(byID[failing.id]?.outcome == .failed(status: 1))
        #expect(byID[busy.id]?.outcome == .busy)
        #expect(byID[cancelled.id]?.outcome == .cancelled)
        #expect(byID[cancelled.id]?.argv == ["install", "--cask", "iterm2"])
    }

    // MARK: - The failure tail rides the draft

    @Test("A failed mutation's draft carries the newest log lines; a success carries none")
    func aFailureDraftCarriesItsLogTail() async throws {
        let harness = CenterHarness(honoursInterrupt: false)

        let failing = harness.center.submit(.install(try Self.target(CenterHarness.wget)))
        await harness.launcher.waitForLaunches(atLeast: 1)
        harness.launcher.launchedProcesses[0].emitStderr("Error: wget: download failed")
        await harness.settle()
        try await harness.finish(call: 0, status: 1)

        let succeeding = harness.center.submit(.install(try Self.target(CenterHarness.iterm)))
        await harness.launcher.waitForLaunches(atLeast: 2)
        try await harness.finish(call: 1, status: 0)

        #expect(failing.outcome == .failed(status: 1))
        #expect(succeeding.outcome == .succeeded)
        let byID = Dictionary(
            harness.recorder.drafts.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(byID[failing.id]?.failureTail.contains("Error: wget: download failed") == true)
        #expect(byID[succeeding.id]?.failureTail.isEmpty == true)
    }

    // MARK: - OA6 sc3, IH1 sc3 — nothing before the terminal outcome

    @Test("A pending mutation and a running mutation each write nothing")
    func nothingIsWrittenBeforeTheTerminalOutcome() async throws {
        let harness = CenterHarness()

        let running = harness.center.submit(.install(try Self.target(CenterHarness.wget)))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let pending = harness.center.submit(.install(try Self.target(CenterHarness.git)))
        await harness.settle()

        // Both exist, neither is terminal, and the process for the first one is
        // genuinely alive — so this is "not yet", not "never started".
        #expect(harness.launcher.launchCount == 1)
        #expect(running.isTerminal == false)
        #expect(pending.isTerminal == false)
        #expect(harness.recorder.drafts.isEmpty, "a draft was written for an in-flight operation")

        // And once they do settle, exactly two arrive.
        try await harness.finish(call: 0)
        try await harness.finish(call: 1)
        #expect(harness.recorder.drafts.count == 2)
    }

    // MARK: - OA6 sc4, IH7 sc1–2 — recording is a side effect, never a precondition

    @Test(
        "An absent and a failing recorder both leave the outcome, the log and the re-snapshot alone",
        arguments: [RecorderKind.working, .absent, .failing]
    )
    func aRecorderFailureNeverReachesTheOperation(kind: RecorderKind) async throws {
        let harness = CenterHarness(history: kind.recorder)
        let terminals = Counter()
        let watcher = Task { [stream = harness.gate.terminals] in
            for await _ in stream { terminals.increment() }
        }
        await harness.settle()

        let item = harness.center.submit(.install(try Self.target(CenterHarness.wget)))
        await harness.launcher.waitForLaunches(atLeast: 1)
        harness.launcher.launchedProcesses[0].emitStdout("==> Pouring\n")
        await harness.settle()
        try await harness.finish(call: 0)
        await harness.settle()

        // Identical in all three worlds: the reported outcome, the log, and the
        // single re-snapshot the terminal owes.
        #expect(item.outcome == .succeeded)
        #expect(item.log.map(\.text) == ["==> Pouring"])
        #expect(terminals.value == 1, "\(kind) forced \(terminals.value) re-snapshots rather than one")
        #expect(harness.gate.isMutating == false)
        watcher.cancel()
    }

    /// Named rather than boolean, so the parameterised case that fails says
    /// which world it was in.
    enum RecorderKind: Sendable, CustomStringConvertible {
        case working
        case absent
        case failing

        @MainActor var recorder: any HistoryRecording {
            switch self {
            case .working: RecordingHistoryRecorder()
            case .absent: NoHistoryRecording()
            case .failing: FailingHistoryRecorder()
            }
        }

        var description: String {
            switch self {
            case .working: "a working recorder"
            case .absent: "an absent recorder"
            case .failing: "a failing recorder"
            }
        }
    }

    // MARK: - IH1 versions, IH2 sc1 — the transition Cellar intended at submission

    @Test("The recorded transition is the one intended at submission, not one observed after")
    func theTransitionIsTheOneIntendedAtSubmission() async throws {
        let harness = CenterHarness()
        let inventory = InstalledFixture.inventory(outdated: [CenterHarness.wget: "1.2.3"])

        let items = harness.center.submitUpgrades(for: [CenterHarness.wget], in: inventory)
        await harness.settle()
        try await harness.finish(call: 0)

        #expect(items.count == 1)
        let draft = try #require(harness.recorder.drafts.first)
        let versions = try #require(draft.versions, "the transition was not carried to the record")
        #expect(versions.from == InstalledFixture.installedVersion)
        #expect(versions.to == "1.2.3")
        #expect(draft.verb == "upgrade")
        #expect(draft.argv == ["upgrade", "--formula", "wget"])
    }

    @Test("A submission with no known transition records none rather than half of one")
    func anUnknownTransitionIsRecordedAsAbsent() async throws {
        let harness = CenterHarness()
        // Nothing in the inventory to derive from: the package is not installed.
        let items = harness.center.submitUpgrades(
            for: [CenterHarness.wget],
            in: InstalledInventory(packages: [])
        )
        await harness.settle()
        try await harness.finish(call: 0)

        #expect(items.count == 1)
        let draft = try #require(harness.recorder.drafts.first)
        #expect(draft.versions == nil, "half a transition was recorded")
        #expect(draft.packageID == CenterHarness.wget)
    }

    /// Settled decision R1: one grouped entry, no per-package attribution, and
    /// **no inventory diffing anywhere** to produce it.
    @Test("Upgrade all writes one grouped entry naming no package and no versions")
    func upgradeAllWritesOneGroupedEntry() async throws {
        let harness = CenterHarness()
        let item = harness.center.submit(.upgradeAll)
        await harness.settle()
        try await harness.finish(call: 0)

        #expect(harness.recorder.drafts.count == 1, "upgrade-all was attributed per package")
        let draft = try #require(harness.recorder.drafts.first)
        #expect(draft.id == item.id)
        #expect(draft.packageID == nil, "the grouped entry named a package")
        #expect(draft.verb == "upgradeAll")
        #expect(draft.versions == nil)
        #expect(draft.argv == ["upgrade"])
        #expect(draft.commandText == "upgrade")
    }

    // MARK: - IH3 sc1–2 — only what Cellar submitted is recorded

    /// The change observer makes an external install **visible**; it must not
    /// make it *recorded*. Settled decision R2: no FSEvents-driven write exists,
    /// so a package that appeared because someone used a Terminal produces a row
    /// in the inventory and no row in the history.
    @Test("A package installed outside Cellar is listed but never logged")
    func anExternalInstallIsNeverLogged() async {
        // A live, attached centre with a real recorder behind it — so "nothing
        // was written" is a claim about a wired seam, not about an idle object.
        let harness = CenterHarness()
        let source = FakeInstalledPayloadSource([
            .formulae(["wget"]),
            .formulae(["wget", "curl"])
        ])
        let store = InstalledStore(source: source)
        let observer = FakeInstalledChangeObserver()
        let clock = TestClock()
        let coordinator = InstalledRefreshCoordinator(
            store: store,
            observer: observer,
            mutations: harness.gate,
            clock: clock
        )
        let loop = Task { await coordinator.run() }

        await coordinator.refresh(using: TestInstallation.appleSilicon)
        #expect(store.inventory.packages.map(\.name) == ["wget"])

        observer.emit()
        await clock.waitForSleepers()
        for _ in 0..<4 {
            await clock.advance(by: .seconds(2))
            for _ in 0..<20 { await Task.yield() }
        }

        // The inventory has genuinely moved — so this is "detected and not
        // logged", not "nothing happened".
        #expect(store.inventory.packages.map(\.name) == ["curl", "wget"])
        #expect(source.callCount == 2)
        #expect(harness.recorder.drafts.isEmpty, "an externally installed package was logged")
        #expect(harness.center.items.isEmpty, "the change signal enqueued an operation")

        // And the same centre does write, for something Cellar itself submits —
        // so the emptiness above is the rule, not a dead seam.
        harness.center.submit(.upgradeAll)
        try? await harness.finish(call: 0)
        #expect(harness.recorder.drafts.count == 1)
        loop.cancel()
    }

    /// Read-only work writes nothing: a refresh, a catalog sync and a detection
    /// are probes, and a probe is not a mutation.
    @Test("An inventory refresh, a catalog sync and a brew detection all write nothing")
    func readOnlyWorkWritesNothing() async {
        let harness = CenterHarness()
        let source = FakeInstalledPayloadSource([.formulae(["wget"]), .formulae(["wget", "curl"])])
        let store = InstalledStore(source: source)

        await store.refresh(using: TestInstallation.appleSilicon)
        await store.refresh(using: TestInstallation.appleSilicon)
        // Detection: pointing the centre at an installation, and repointing it.
        harness.center.attach(installation: TestInstallation.appleSilicon)
        harness.center.attach(installation: TestInstallation.intel)
        harness.center.attach(installation: nil)
        await harness.settle()

        #expect(source.callCount == 2, "the refreshes did not run")
        #expect(store.inventory.packages.isEmpty == false)
        #expect(harness.recorder.drafts.isEmpty, "a read-only path wrote a history entry")
        #expect(harness.center.items.isEmpty)
    }

    /// The rejected alternative, asserted structurally: deriving the transition
    /// by diffing an inventory snapshot either side of the operation would make
    /// the entry depend on watcher timing.
    @Test("No inventory snapshot is diffed to build a record")
    func noInventoryDiffingProducesARecord() throws {
        let source = try Self.source(of: "OperationCenter.swift")

        for forbidden in ["snapshotBefore", "snapshotAfter", "diff(", "beforeSnapshot"] {
            #expect(source.contains(forbidden) == false, "\(forbidden) suggests snapshot diffing")
        }
        // The transition comes from the inventory handed to the submission,
        // which is the only inventory this file reads at all.
        #expect(source.contains("versions: VersionTransition?"))
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
