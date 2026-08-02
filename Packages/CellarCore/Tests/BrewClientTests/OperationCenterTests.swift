import CellarTestSupport
import Foundation
import Synchronization
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The store that turns a typed command into a queue item, drives the mutation
/// gate, and projects both the always-visible summary and the detail list.
///
/// Built on the `InstalledStore` exemplar — one `@MainActor @Observable` class,
/// acquisition below it — and covering the rules the SwiftUI views read, so the
/// app target owns no rule at all (design D4, D10). Nothing spawns `brew` and
/// nothing mutates a real Homebrew (D12).
@MainActor
@Suite("Operation center submissions", .timeLimit(.minutes(1)))
struct OperationCenterTests {

    // MARK: - One submission, one item (OA2 sc1–2)

    @Test("A submission produces one item whose identity and copy text never change")
    func aSubmissionProducesOneStableItem() async throws {
        let harness = CenterHarness()
        let command = MutationCommand.install(PackageTarget(CenterHarness.iterm)!)

        let item = harness.center.submit(command)
        await harness.settle()

        let id = item.id
        let pendingCopy = item.copyText
        #expect(harness.center.items.count == 1)
        #expect(item.displayCommand == "brew install --cask iterm2")
        #expect(pendingCopy == "brew install --cask iterm2")

        try await harness.finish(call: 0)

        #expect(item.id == id, "the identity changed between states")
        #expect(item.copyText == pendingCopy, "copy text differed once terminal")
        #expect(item.displayCommand == "brew install --cask iterm2")
        #expect(item.outcome == .succeeded)
        #expect(item.isTerminal)
    }

    @Test("The item carries the exact argv in every state")
    func theItemCarriesTheExactArgv() async throws {
        let harness = CenterHarness()
        let item = harness.center.submit(.install(PackageTarget(CenterHarness.iterm)!))
        await harness.settle()

        #expect(item.arguments == ["install", "--cask", "iterm2"])
        try await harness.finish(call: 0)
        #expect(item.arguments == ["install", "--cask", "iterm2"])

        // And that is the vector that reached the process seam.
        #expect(harness.launcher.recordedSpecs.map(\.arguments) == [item.arguments])
    }

    // MARK: - The bounded log ring (OA3 sc3)

    @Test("The log drains verbatim, tagged, in emission order")
    func theLogDrainsVerbatim() async throws {
        let harness = CenterHarness()
        let item = harness.center.submit(.install(PackageTarget(CenterHarness.wget)!))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let process = harness.launcher.launchedProcesses[0]

        process.emitStdout("==> Downloading\n")
        process.emitStderr("Warning: something\n")
        process.emitStdout("==> Pouring\n")
        await harness.settle()

        #expect(item.log.map(\.text) == ["==> Downloading", "Warning: something", "==> Pouring"])
        #expect(item.log.map(\.stream) == [.stdout, .stderr, .stdout])
        #expect(item.isLogTruncated == false)

        // Readable while still running, which is the point of streaming.
        #expect(item.isTerminal == false)
        try await harness.finish(call: 0)
        #expect(item.log.count == 3, "the terminal outcome dropped the log")
    }

    @Test("The 2,001st line evicts the oldest and raises the truncation marker")
    func theLogRingEvictsTheOldest() async throws {
        let harness = CenterHarness()
        let item = harness.center.submit(.install(PackageTarget(CenterHarness.wget)!))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let process = harness.launcher.launchedProcesses[0]

        for index in 0..<ActivityItem.logCapacity {
            process.emitStdout("line \(index)\n")
        }
        // 2,000 lines cross a stream and a main-actor hop, so wait for the
        // drain to catch up rather than for a fixed number of yields.
        await harness.poll { item.log.count >= ActivityItem.logCapacity }

        #expect(item.log.count == ActivityItem.logCapacity)
        #expect(item.isLogTruncated == false)
        #expect(item.log.first?.text == "line 0")

        process.emitStdout("line 2000\n")
        await harness.poll { item.isLogTruncated }

        #expect(item.log.count == ActivityItem.logCapacity, "the ring grew past its capacity")
        #expect(item.isLogTruncated, "no truncation marker after eviction")
        #expect(item.log.first?.text == "line 1", "the oldest line was not the one evicted")
        #expect(item.log.last?.text == "line 2000")
        // Still verbatim and still tagged.
        #expect(item.log.allSatisfy { $0.stream == .stdout })

        try await harness.finish(call: 0)
    }

    // MARK: - Per-package fan-out (PM2 sc2 — the settled shape)

    /// The user ruling: a selected upgrade is N ordinary `.upgrade(PackageTarget(id)!)`
    /// submissions, not one grouped invocation. There is no `upgradeSelected`
    /// case anywhere in the API.
    @Test("A selection fans out into exactly one operation per package, in order")
    func aSelectionFansOutPerPackage() async throws {
        let harness = CenterHarness()

        let items = harness.center.submitUpgrades(for: [CenterHarness.wget, CenterHarness.git, CenterHarness.iterm])
        await harness.settle()

        #expect(items.count == 3)
        #expect(harness.center.items.count == 3)
        #expect(items.map(\.arguments) == [
            ["upgrade", "--formula", "wget"],
            ["upgrade", "--formula", "git"],
            ["upgrade", "--cask", "iterm2"]
        ])

        // No argv names more than one package.
        for item in items {
            let names = item.arguments.filter { !$0.hasPrefix("-") && $0 != "upgrade" }
            #expect(names.count == 1, "an argv named \(names.count) packages")
        }

        for index in 0..<3 { try await harness.finish(call: index) }
    }

    /// The reason the fan-out was chosen over kind-grouped argv: attribution.
    @Test("A mid-batch failure attributes to exactly one package")
    func aMidBatchFailureAttributesToOnePackage() async throws {
        let harness = CenterHarness()
        let items = harness.center.submitUpgrades(for: [CenterHarness.wget, CenterHarness.git, CenterHarness.iterm])
        await harness.settle()

        try await harness.finish(call: 0, status: 0)
        try await harness.finish(call: 1, status: 1)
        try await harness.finish(call: 2, status: 0)

        #expect(items[0].outcome == .succeeded)
        #expect(items[1].outcome == .failed(status: 1))
        #expect(items[2].outcome == .succeeded, "a sibling was poisoned by the failing item")

        #expect(items[1].packageID == CenterHarness.git)
        #expect(items.count(where: { $0.outcome?.isFailure == true }) == 1)
    }

    /// A pinned formula is not named in the selected-upgrade expansion over the
    /// outdated set, and no unpin is submitted on its behalf (PM2 sc4).
    @Test("A pinned formula is never named and never unpinned to upgrade it")
    func pinnedFormulaeAreNeverForceUpgraded() async throws {
        let harness = CenterHarness()
        let inventory = InstalledInventory(packages: [
            InstalledDeriveTests.formula(
                name: "wget", installed: "1.25.0", published: "1.26.0", snapshotOutdated: true
            ),
            InstalledDeriveTests.formula(
                name: "pinned-tool", installed: "1.0", published: "2.0",
                snapshotOutdated: false, isPinned: true, pinnedVersion: "1.0"
            )
        ])

        let items = harness.center.submitUpgradesForOutdated(in: inventory)
        await harness.settle()

        #expect(items.map(\.arguments) == [["upgrade", "--formula", "wget"]])
        let everyArgument = items.flatMap(\.arguments)
        #expect(everyArgument.contains("pinned-tool") == false)
        #expect(everyArgument.contains("unpin") == false)

        // And upgrade-all names nothing at all, so it cannot name it either.
        let all = harness.center.submit(.upgradeAll)
        #expect(all.arguments == ["upgrade"])

        try await harness.finish(call: 0)
        try await harness.finish(call: 1)
    }

}
