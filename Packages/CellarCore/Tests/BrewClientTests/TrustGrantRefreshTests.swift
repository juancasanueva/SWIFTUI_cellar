import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// `package-trust` PT2 :114-132 — the grant read rides the taps domain, and it
/// rides it as a passenger: it never changes the outcome, the count, or the
/// timing of the refresh it travels with (DD-3, DD-4).
@MainActor
@Suite("Per-package trust refresh", .timeLimit(.minutes(1)))
struct TrustGrantRefreshTests {
    private static let tapPayload = """
    [{"name":"acme/tools","repo":"tools","formula_names":["acme/tools/widget"],"trusted":false}]
    """
    private static let grantPayload = """
    {"taps":[],"formulae":["acme/tools/widget"],"casks":[],"commands":[]}
    """

    // MARK: - PT2 :164-170 — both reads, once, overlapping

    /// Overlap is asserted the only way it can be honestly asserted: **both
    /// processes are alive at the same time**. A sequential implementation could
    /// never reach two live launches, so this expectation fails the day the
    /// `async let` becomes an `await`, rather than merely getting slower.
    @Test("Both reads are issued once for one refresh and overlap")
    func bothReadsAreIssuedOnceForOneRefreshAndOverlap() async throws {
        let launcher = ControllableProcessLauncher()
        let taps = TapStore(source: BrewTapPayloadSource(launcher: launcher))
        let grants = TrustGrantStore(source: BrewTrustGrantPayloadSource(launcher: launcher))
        let coordinator = TapRefreshCoordinator(store: taps, grants: grants)

        let refresh = Task { await coordinator.refresh(using: TestInstallation.appleSilicon) }
        await launcher.waitForLaunches(atLeast: 2)

        // Two live processes: the second read started before the first finished.
        #expect(launcher.launchedProcesses.allSatisfy { $0.hasTerminated == false })
        #expect(Set(launcher.recordedSpecs.map(\.arguments)) == [
            ["tap-info", "--installed", "--json"],
            ["trust", "--json", "v1"]
        ])

        for (index, arguments) in launcher.recordedSpecs.map(\.arguments).enumerated() {
            let process = launcher.launchedProcesses[index]
            process.emitStdout(arguments.first == "trust" ? Self.grantPayload : Self.tapPayload)
            process.terminate(with: BrewExit(status: 0, reason: .exited))
        }
        await refresh.value

        // Exactly one of each, and nothing else was read at all — no installed
        // inventory, no catalog. The coordinator holds no store that could.
        #expect(launcher.launchCount == 2)
        #expect(taps.inventory.taps.map(\.name) == ["acme/tools"])
        #expect(grants.grants.ledger?.formulae == ["acme/tools/widget"])
        #expect(taps.state == .loaded)
        #expect(grants.state == .loaded)
    }

    // MARK: - PT2 :172-178 — a failing grant read never fails a tap refresh

    @Test("A degraded grant read never fails the tap receipt")
    func aDegradedGrantReadNeverFailsTheTapReceipt() async throws {
        // Arm one: the grant source throws outright.
        let thrown = try await Self.receipt(
            tap: GatedTapPayloadSource([.payload(Self.tapPayload)]),
            grant: FakeTrustGrantPayloadSource([
                .failure(.commandFailed(status: 1, message: "Error: Unknown command: trust"))
            ])
        )

        #expect(thrown.results == [.taps: .refreshed], "a failed grant read failed the tap receipt")
        #expect(thrown.tapRefreshCount == 1, "the taps domain refreshed \(thrown.tapRefreshCount) times")
        #expect(thrown.taps.inventory.taps.map(\.name) == ["acme/tools"])
        #expect(thrown.taps.state == .loaded)
        // …and the grant state degrades to `unreported`, never to a count.
        #expect(thrown.grants.grants == .unreported)
        #expect(thrown.grants.grants.entryCount == nil)

        // Arm two: the grant source never answers. The tap snapshot must be
        // adopted while that read is still outstanding — "undelayed" means the
        // tap store does not wait for a stranger.
        let gate = InstalledMutationGate()
        let registry = MutationRefreshRegistry()
        let grantSource = FakeTrustGrantPayloadSource([.failure(.cancelled)], gated: true)
        let taps = TapStore(source: GatedTapPayloadSource([.payload(Self.tapPayload)]))
        let grants = TrustGrantStore(source: grantSource)
        let coordinator = TapRefreshCoordinator(
            store: taps,
            grants: grants,
            mutations: gate,
            refreshRegistry: registry
        )
        let runner = Task { await coordinator.run() }
        defer { runner.cancel() }

        let refresh = Task { await coordinator.refresh(using: TestInstallation.appleSilicon) }
        await grantSource.waitForCalls(atLeast: 1)
        await Self.untilLoaded(taps)

        #expect(taps.inventory.taps.map(\.name) == ["acme/tools"], "the tap snapshot waited for the grant read")
        #expect(grants.grants == .unreported)

        grantSource.releaseAll()
        await refresh.value
        #expect(grants.grants == .unreported, "an unanswered grant read invented a report")
        #expect(taps.state == .loaded)
    }

    // MARK: - PT2 :156-162 — no per-package invalidation domain exists

    /// **DD-3.** A domain no Cellar command could ever invalidate would be dead
    /// declaration surface across five command families. The absence is pinned
    /// here so a later change adding one has to argue with a test rather than
    /// with a comment.
    @Test("No per-package invalidation domain exists")
    func noPerPackageInvalidationDomainExists() throws {
        let formula = try #require(PackageTarget(PackageID(kind: .formula, name: "wget")))
        let tap = try #require(TapName("acme/tools"))
        let service = try #require(ServiceTarget(name: "thing"))

        var declared: [InvalidationScope] = [
            MutationCommand.update, .upgradeAll, .install(formula), .uninstall(formula),
            .upgrade(formula), .reinstall(formula)
        ].map(\.invalidates)
        declared += [
            TapCommand.addTap(tap), .trustTap(tap), .untrustTap(tap), .removeTap(tap),
            .forceRemoveTap(ForceUntapEvidence(tap: tap, affected: [], isComplete: true))
        ].map(\.invalidates)
        declared += ServiceCommand.allVerbs(for: service).map(\.invalidates)
        declared += [
            CleanupCommand(scope: .global),
            CleanupCommand(scope: .autoremove)
        ].map(\.invalidates)

        // Positively anchored: the enumeration really did walk every family.
        #expect(declared.count == 17, "the invalidation enumeration collapsed to \(declared.count)")
        #expect(declared.contains(.services))
        #expect(declared.contains { $0.contains(.taps) })

        let union = declared.reduce(into: InvalidationScope()) { $0.formUnion($1) }
        #expect(union == [.installedInventory, .services, .taps, .diskUsage])
        #expect(union.rawValue == 0b1111, "a fifth domain bit is declared somewhere")

        // …and the type itself has exactly those four members, so there is no
        // per-package domain waiting to be declared either.
        let source = try Self.brewClientSource("BrewMutating.swift")
        let members = source
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("public static let ") && $0.contains("InvalidationScope(rawValue:") }
        // Five since the npm source landed. The fifth is `npmInventory`, and it
        // is deliberately outside the brew union asserted above: a `brew info`
        // re-snapshot cannot observe an npm change, so npm declares a domain of
        // its own rather than widening one of brew's (design D11). The census
        // stays exact so a *sixth*, undeclared member is still a failure.
        #expect(members.count == 5, "InvalidationScope grew a member: \(members)")
        for name in ["installedInventory", "services", "taps", "diskUsage", "npmInventory"] {
            #expect(members.contains { $0.contains("let \(name) =") })
        }
        for absent in ["TrustGrant", "packageTrust", "perPackage", "grantsIndividually"] {
            #expect(source.contains(absent) == false, "BrewMutating reached for \(absent)")
        }

        // The read itself declares nothing: it is a `read`, not a mutation, and
        // it is not on the spine at all (PM10 :160-167).
        #expect(BrewTrustGrantPayloadSource.command.kind == .read)
        #expect((BrewTrustGrantPayloadSource.command as Any) is (any BrewMutating) == false)
    }

    // MARK: - Harness

    private struct RefreshOutcome {
        let results: [RefreshDomain: RefreshResult]
        let tapRefreshCount: Int
        let taps: TapStore
        let grants: TrustGrantStore
    }

    /// Drives one tap-domain mutation terminal through a real coordinator and
    /// returns the receipt it produced.
    private static func receipt(
        tap: GatedTapPayloadSource,
        grant: FakeTrustGrantPayloadSource
    ) async throws -> RefreshOutcome {
        let gate = InstalledMutationGate()
        let registry = MutationRefreshRegistry()
        let taps = TapStore(source: tap)
        let grants = TrustGrantStore(source: grant)
        let coordinator = TapRefreshCoordinator(
            store: taps,
            grants: grants,
            mutations: gate,
            refreshRegistry: registry
        )
        let runner = Task { await coordinator.run() }
        defer { runner.cancel() }
        let refreshes = Counter()
        let watcher = Task { for await _ in gate.terminals { refreshes.increment() } }
        defer { watcher.cancel() }

        await coordinator.refresh(using: TestInstallation.appleSilicon)

        let token = MutationOperationToken()
        await registry.register(token, domains: [.taps])
        let waiter = Task { await registry.wait(for: token) }
        gate.begin()
        gate.end(event: MutationTerminalEvent(
            token: token,
            domain: .taps,
            installationURL: TestInstallation.appleSilicon.executableURL
        ))
        let receipt = try #require(await waiter.value)
        await TestPoll.until(refreshes.value >= 1)

        return RefreshOutcome(
            results: receipt.results,
            tapRefreshCount: refreshes.value,
            taps: taps,
            grants: grants
        )
    }

    /// A bounded wait for a `@MainActor` store, which `TestPoll` cannot express
    /// because its condition is a `Sendable` autoclosure.
    private static func untilLoaded(_ store: TapStore) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while store.state != .loaded, ContinuousClock.now < deadline { await Task.yield() }
    }

    private static func brewClientSource(_ name: String) throws -> String {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrewClient")
        return try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
