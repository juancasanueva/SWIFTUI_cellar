import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

@Suite("Mutation refresh receipts", .timeLimit(.minutes(1)))
struct MutationRefreshReceiptTests {
    private let installationURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")

    @Test("A receipt completes only after every registered domain settles")
    func receiptWaitsForEveryDomain() async throws {
        let registry = MutationRefreshRegistry()
        let token = MutationOperationToken()
        await registry.register(token, domains: [.taps, .installedInventory])
        let waiter = Task { await registry.wait(for: token) }

        let tapsAccepted = await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: installationURL),
            with: .refreshed
        )
        #expect(tapsAccepted)
        #expect(await registry.isRegistered(token))

        let installedAccepted = await registry.complete(
            MutationTerminalEvent(
                token: token,
                domain: .installedInventory,
                installationURL: installationURL
            ),
            with: .refreshed
        )
        let receipt = try #require(await waiter.value)

        #expect(installedAccepted)
        #expect(receipt.token == token)
        #expect(receipt.results == [.taps: .refreshed, .installedInventory: .refreshed])
        #expect(await registry.isRegistered(token) == false)
    }

    @Test(
        "Every bounded refresh result is preserved in the keyed receipt",
        arguments: [
            RefreshResult.failed,
            .brewUnavailable,
            .installationChanged,
            .cancelled,
            .teardown
        ]
    )
    func boundedResultsSettle(result: RefreshResult) async throws {
        let registry = MutationRefreshRegistry()
        let token = MutationOperationToken()
        await registry.register(token, domains: [.services])
        let waiter = Task { await registry.wait(for: token) }

        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .services, installationURL: installationURL),
            with: result
        ))
        let receipt = try #require(await waiter.value)
        #expect(receipt.results == [.services: result])
    }

    @Test("Duplicate and unknown completions are ignored")
    func duplicateAndUnknownCompletionsAreIgnored() async throws {
        let registry = MutationRefreshRegistry()
        let token = MutationOperationToken()
        let unknown = MutationOperationToken()
        await registry.register(token, domains: [.taps, .installedInventory])

        #expect(await registry.complete(
            MutationTerminalEvent(token: unknown, domain: .taps, installationURL: installationURL),
            with: .refreshed
        ) == false)
        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .services, installationURL: installationURL),
            with: .refreshed
        ) == false)
        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: installationURL),
            with: .refreshed
        ))
        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: installationURL),
            with: .failed
        ) == false)

        let waiter = Task { await registry.wait(for: token) }
        #expect(await registry.complete(
            MutationTerminalEvent(
                token: token,
                domain: .installedInventory,
                installationURL: installationURL
            ),
            with: .refreshed
        ))
        let receipt = try #require(await waiter.value)
        #expect(receipt.results[.taps] == .refreshed, "a duplicate rewrote the first result")
    }

    @Test("Completion before a consumer is retained, while unregistered events are discarded")
    func noConsumerPathsAreBounded() async throws {
        let registry = MutationRefreshRegistry()
        let token = MutationOperationToken()
        let unregistered = MutationOperationToken()
        await registry.register(token, domains: [.taps])

        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: installationURL),
            with: .refreshed
        ))
        #expect(await registry.complete(
            MutationTerminalEvent(
                token: unregistered,
                domain: .taps,
                installationURL: installationURL
            ),
            with: .refreshed
        ) == false)

        let receipt = try #require(await registry.wait(for: token))
        #expect(receipt.results == [.taps: .refreshed])
    }

    @Test("Cancelling a waiter removes its registration")
    func waiterCancellationRemovesRegistration() async {
        let registry = MutationRefreshRegistry()
        let token = MutationOperationToken()
        await registry.register(token, domains: [.taps])
        let waiter = Task { await registry.wait(for: token) }

        waiter.cancel()
        #expect(await waiter.value == nil)
        #expect(await registry.isRegistered(token) == false)
        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: installationURL),
            with: .refreshed
        ) == false)
    }

    @Test("Registry shutdown resolves every outstanding domain as teardown")
    func shutdownResolvesOutstandingDomains() async throws {
        let registry = MutationRefreshRegistry()
        let first = MutationOperationToken()
        let second = MutationOperationToken()
        await registry.register(first, domains: [.taps, .installedInventory])
        await registry.register(second, domains: [.services])
        let firstWaiter = Task { await registry.wait(for: first) }
        let secondWaiter = Task { await registry.wait(for: second) }

        await registry.shutdown()

        let firstReceipt = try #require(await firstWaiter.value)
        let secondReceipt = try #require(await secondWaiter.value)
        #expect(firstReceipt.results == [.taps: .teardown, .installedInventory: .teardown])
        #expect(secondReceipt.results == [.services: .teardown])
    }

    // MARK: - TM9 :364-371 — five commands, four terminals

    /// TM9's enumeration was three commands and said only force untap also
    /// refreshes installed inventory. Both halves stop being true the moment
    /// trust exists: a grant is exactly what makes `brew info --installed` start
    /// or stop reporting a package's `tap` (obs #7724).
    ///
    /// Every terminal counts, including the two that never produced output —
    /// a launch failure and a cancellation before spawn — because "exactly one
    /// refresh per declared domain, never zero and never two" is a statement
    /// about terminals, not about successes.
    @MainActor
    @Test(
        "Every tap terminal refreshes its declared domains exactly once",
        arguments: TapTerminal.allCases
    )
    func everyTapTerminalRefreshesItsDeclaredDomainsExactlyOnce(
        terminal: TapTerminal
    ) async throws {
        let tap = try #require(TapName("acme/tools"))
        let force = try #require(TapCommand.forceUntap(evidence: ForceUntapEvidence(
            tap: tap,
            affected: [PackageID(kind: .formula, name: "widget")],
            isComplete: true
        )))
        let commands: [(name: String, command: TapCommand, refreshesInventory: Bool)] = [
            ("add", try #require(TapCommand.add("acme/tools")), false),
            ("plain untap", try #require(TapCommand.untap("acme/tools")), false),
            ("force untap", force, true),
            ("trust", try #require(TapCommand.trust("acme/tools")), true),
            ("untrust", try #require(TapCommand.untrust("acme/tools")), true)
        ]

        // Positively anchored: five commands, and the split really is 2 / 3.
        #expect(commands.count == 5)
        #expect(commands.filter(\.refreshesInventory).count == 3)

        for entry in commands {
            let counts = try await refreshCounts(for: entry.command, terminal: terminal)

            #expect(
                counts.taps == 1,
                "\(entry.name) refreshed taps \(counts.taps) times on \(terminal.rawValue)"
            )
            #expect(
                counts.installed == (entry.refreshesInventory ? 1 : 0),
                "\(entry.name) refreshed installed inventory \(counts.installed) times on \(terminal.rawValue)"
            )
            // No tap command may reach a catalog domain at all — there is none in
            // the scope to reach, and the services counter proves the gates it
            // does not declare stay shut.
            #expect(entry.command.invalidates.isDisjoint(with: .services))
            #expect(counts.services == terminal.blockerServiceTerminals)
        }
    }

    /// The four terminals TM9 enumerates, including the two that never spawn.
    enum TapTerminal: String, CaseIterable, Sendable {
        case success
        case failure
        case launchFailure = "launch failure"
        case cancellationBeforeSpawn = "cancellation before spawn"

        /// The cancellation arm needs a running command to hold the FIFO open so
        /// the tap command can be cancelled while still queued. That blocker is a
        /// **services** command precisely so it cannot contribute to either
        /// counter under test; it contributes one services terminal of its own,
        /// and that is stated rather than absorbed.
        var blockerServiceTerminals: Int {
            self == .cancellationBeforeSpawn ? 1 : 0
        }
    }

    @MainActor
    private func refreshCounts(
        for command: TapCommand,
        terminal: TapTerminal
    ) async throws -> (taps: Int, installed: Int, services: Int) {
        let launcher = ControllableProcessLauncher()
        let tapsGate = InstalledMutationGate()
        let installedGate = InstalledMutationGate()
        let servicesGate = InstalledMutationGate()
        let center = OperationCenter(
            gates: MutationGates([
                (.taps, tapsGate),
                (.installedInventory, installedGate),
                (.services, servicesGate)
            ]),
            launcherFactory: { _ in launcher }
        )
        center.attach(installation: TestInstallation.appleSilicon)
        let taps = Counter()
        let installed = Counter()
        let services = Counter()
        let watchers = [
            Task { for await _ in tapsGate.terminals { taps.increment() } },
            Task { for await _ in installedGate.terminals { installed.increment() } },
            Task { for await _ in servicesGate.terminals { services.increment() } }
        ]
        defer { watchers.forEach { $0.cancel() } }
        // Let the three watchers actually start consuming before anything can
        // settle, so a zero below is a missing refresh rather than a race.
        await settle()

        switch terminal {
        case .success, .failure:
            _ = center.submit(command)
            await launcher.waitForLaunches(atLeast: 1)
            launcher.launchedProcesses[0].terminate(
                with: BrewExit(status: terminal == .success ? 0 : 1, reason: .exited)
            )
        case .launchFailure:
            launcher.failLaunch(with: BrewValidationError.notExecutable(
                URL(fileURLWithPath: "/configured/not-brew")
            ))
            _ = center.submit(command)
        case .cancellationBeforeSpawn:
            let blocker = try #require(ServiceCommand.start(service: "acme"))
            _ = center.submit(blocker)
            await launcher.waitForLaunches(atLeast: 1)
            let pending = center.submit(command)
            await settle()
            center.cancel(pending)
            await settle()
            #expect(launcher.launchCount == 1, "the cancelled tap command spawned anyway")
            launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        }
        // Every command under test declares taps, so waiting on that counter is
        // the one bounded wait that is correct for all five.
        await TestPoll.until(taps.value >= 1)
        await settle()
        return (taps.value, installed.value, services.value)
    }

    private func settle() async {
        for _ in 0..<500 { await Task.yield() }
    }
}
