import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The one main-isolated crossing point in `BrewClient`.
///
/// Built from the two exemplars M2-0 corrected: a single-flight slot keyed by
/// the request, and an ordinal-guarded adoption that discards a snapshot
/// overtaken by a fresher one (design D6).
@MainActor
@Suite("Installed store", .timeLimit(.minutes(1)))
struct InstalledStoreTests {
    /// Lets pending main-actor work run without depending on wall-clock time.
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    // MARK: - One invocation per refresh (II1)

    @Test("One completed refresh records exactly one brew invocation")
    func oneRefreshIsOneInvocation() async throws {
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: String(decoding: try InstalledFixture.data(), as: UTF8.self))
        ])
        let store = InstalledStore(source: BrewInfoPayloadSource(launcher: launcher))

        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(launcher.launchCount == 1)
        let spec = try #require(launcher.specs.first)
        #expect(spec.arguments == ["info", "--installed", "--json=v2"])
        #expect(store.inventory.packages.isEmpty == false)
    }

    @Test("Outdated, pinned and dependency-only state all come from that one invocation")
    func derivedFactsRequireNoExtraInvocation() async throws {
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: String(decoding: try InstalledFixture.data(), as: UTF8.self))
        ])
        let store = InstalledStore(source: BrewInfoPayloadSource(launcher: launcher))

        await store.refresh(using: TestInstallation.appleSilicon)

        // All three questions answered off the resident inventory.
        #expect(store.inventory.outdatedCount == 2)
        #expect(store.inventory.packages.contains { $0.isPinned })
        #expect(store.inventory.packages.contains { !$0.isOnRequest })
        #expect(
            store.inventory.packages(includingDependencies: false).count
                < store.inventory.packages.count
        )
        #expect(launcher.launchCount == 1)
    }

    // MARK: - Request-keyed single flight (II10 sc4)

    @Test("Two overlapping refreshes perform one acquisition and see the same inventory")
    func overlappingRefreshesCoalesce() async {
        let source = FakeInstalledPayloadSource([.formulae(["wget"])], gated: true)
        let store = InstalledStore(source: source)

        let first = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)
        let second = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await settle()

        #expect(source.callCount == 1)

        source.release()
        await first.value
        await second.value

        #expect(source.callCount == 1)
        #expect(store.inventory.packages.map(\.name) == ["wget"])
    }

    @Test("A refresh requested after the previous settled takes a fresh snapshot")
    func refreshAfterSettledIsFresh() async {
        let source = FakeInstalledPayloadSource([
            .formulae(["wget"]),
            .formulae(["wget", "curl"])
        ])
        let store = InstalledStore(source: source)

        await store.refresh(using: TestInstallation.appleSilicon)
        #expect(store.inventory.packages.map(\.name) == ["wget"])

        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(source.callCount == 2)
        #expect(store.inventory.packages.map(\.name) == ["curl", "wget"])
    }

    @Test("A refresh under a different installation does not join the one in flight")
    func differentInstallationDoesNotJoin() async {
        let source = FakeInstalledPayloadSource([
            .formulae(["from-apple-silicon"]),
            .formulae(["from-intel"])
        ], gated: true)
        let store = InstalledStore(source: source)

        let first = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)
        let second = Task { await store.refresh(using: TestInstallation.intel) }
        await source.waitForCalls(atLeast: 2)

        #expect(source.callCount == 2)
        #expect(source.installations.map(\.executableURL) == [
            TestInstallation.appleSilicon.executableURL,
            TestInstallation.intel.executableURL
        ])

        source.release()
        await first.value
        await second.value
    }

    // MARK: - Ordinal-guarded adoption

    /// Two refreshes are only ever in flight together when they ask *different*
    /// questions — same-request work coalesces by construction. So the
    /// out-of-order case is exactly this: the user repoints `brew`, the new
    /// installation answers first, and the old one settles late.
    @Test("A late adoption of an older snapshot is discarded, not installed")
    func lateOlderAdoptionIsDiscarded() async {
        let source = FakeInstalledPayloadSource([
            .formulae(["older-answer"]),
            .formulae(["newer-answer"])
        ], gated: true)
        let store = InstalledStore(source: source)

        let older = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)
        let newer = Task { await store.refresh(using: TestInstallation.intel) }
        await source.waitForCalls(atLeast: 2)

        source.release(call: 1)
        await newer.value
        #expect(store.inventory.packages.map(\.name) == ["newer-answer"])

        source.release(call: 0)
        await older.value
        await settle()

        #expect(store.inventory.packages.map(\.name) == ["newer-answer"])
    }

    // MARK: - Failure and absence (II9)

    @Test("A failed refresh keeps the last good inventory and reports the failure")
    func failureKeepsTheLastGoodInventory() async {
        let source = FakeInstalledPayloadSource([
            .formulae(["wget"]),
            .failure(.commandFailed(status: 1, message: "Error: locked"))
        ])
        let store = InstalledStore(source: source)

        await store.refresh(using: TestInstallation.appleSilicon)
        #expect(store.state == .loaded)

        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(store.state == .failed(.commandFailed(status: 1, message: "Error: locked")))
        #expect(store.inventory.packages.map(\.name) == ["wget"])
    }

    @Test("A malformed payload is a failure, not an empty inventory")
    func malformedPayloadKeepsTheLastGoodInventory() async {
        let source = FakeInstalledPayloadSource([
            .formulae(["wget"]),
            .payload("this is not the documented envelope")
        ])
        let store = InstalledStore(source: source)

        await store.refresh(using: TestInstallation.appleSilicon)
        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(store.state == .failed(.malformedPayload))
        #expect(store.inventory.packages.map(\.name) == ["wget"])
    }

    @Test("No installation clears to an empty inventory, throws nothing, spawns nothing")
    func absentBrewSpawnsNothing() async {
        let source = FakeInstalledPayloadSource([.formulae(["wget"])])
        let store = InstalledStore(source: source)

        await store.refresh(using: nil)

        #expect(store.inventory.isEmpty)
        #expect(source.callCount == 0)
        #expect(store.state == .brewAbsent(.notInstalled(.standard)))
        #expect(store.absence?.installGuidance == BrewInstallGuidance.standard)
    }

    @Test("An invalid configured path is guidance carrying the rejection reason")
    func invalidConfiguredPathIsGuidance() async {
        let configured = URL(fileURLWithPath: "/Users/tester/brew")
        let source = FakeInstalledPayloadSource([.formulae(["wget"])])
        let store = InstalledStore(source: source)

        await store.refresh(for: .invalid(configured, .notExecutable(configured)))

        #expect(store.inventory.isEmpty)
        #expect(source.callCount == 0)
        #expect(
            store.state
                == .brewAbsent(.configuredPathRejected(configured, .notExecutable(configured)))
        )
        // The reason is readable, and it is not an error state.
        #expect(store.absence?.rejectionReason == .notExecutable(configured))
        #expect(store.absence?.installGuidance == nil)
    }

    @Test("A configured path that vanished is distinct from no brew at all")
    func missingConfiguredPathIsItsOwnGuidance() async {
        let configured = URL(fileURLWithPath: "/Users/tester/brew")
        let store = InstalledStore(source: FakeInstalledPayloadSource([.formulae(["wget"])]))

        await store.refresh(for: .configuredPathMissing(configured))

        #expect(store.state == .brewAbsent(.configuredPathMissing(configured)))
        #expect(store.state != .brewAbsent(.notInstalled(.standard)))
    }

    @Test("The inventory populates when brew appears, with no restart")
    func inventoryPopulatesWhenBrewAppears() async {
        let source = FakeInstalledPayloadSource([.formulae(["wget", "curl"])])
        let store = InstalledStore(source: source)

        await store.refresh(for: .absent)
        #expect(store.inventory.isEmpty)

        let installation = TestInstallation.appleSilicon
        await store.refresh(
            for: .detected(installation)
        )

        #expect(store.state == .loaded)
        #expect(store.inventory.packages.map(\.name) == ["curl", "wget"])
        #expect(source.callCount == 1)
    }
}
