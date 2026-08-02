import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog
/// Freshness: the two absorbed M2-1 defects around the single-flight slot —
/// a signal answered by a pre-signal acquisition (D8b), and a reset that
/// stranded the slot (D8c). Both are `installed-inventory` II10.
@MainActor
@Suite("Installed store freshness", .timeLimit(.minutes(1)))
struct InstalledStoreFreshnessTests {
    /// Lets pending main-actor work run without depending on wall-clock time.
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    // MARK: - Invalidation marks (D8b — II10 sc6)

    /// The M2-1 defect this change absorbs: a change signal arriving *during* an
    /// acquisition was answered by that acquisition, so the inventory could
    /// settle on state observed strictly before the change it was told about.
    /// The single-flight slot is right; what it lacked was a freshness mark.
    @Test("A refresh requested after an invalidation does not join the stale acquisition")
    func invalidationPreventsJoiningAStaleAcquisition() async {
        let source = FakeInstalledPayloadSource([
            .formulae(["wget"]),
            .formulae(["wget", "curl"])
        ], gated: true)
        let store = InstalledStore(source: source)

        let stale = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)

        // The external change lands after the acquisition started: whatever it
        // is about to answer with was observed before the change.
        store.invalidate()

        let fresh = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 2)

        #expect(source.callCount == 2, "the post-signal refresh joined a pre-signal acquisition")

        source.release()
        await stale.value
        await fresh.value
        await settle()

        #expect(store.inventory.packages.map(\.name) == ["curl", "wget"])
    }

    /// The complement, and the reason the mark is `>=` rather than `>`: a signal
    /// that arrived *before* the acquisition started is already covered by it,
    /// so joining is correct and a second invocation would be waste.
    @Test("A refresh whose invalidation predates the acquisition still joins it")
    func refreshInvalidatedBeforeTheAcquisitionStillJoins() async {
        let source = FakeInstalledPayloadSource([
            .formulae(["wget"]),
            .formulae(["wget", "curl"])
        ], gated: true)
        let store = InstalledStore(source: source)

        store.invalidate()
        let first = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)
        let second = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await settle()

        #expect(source.callCount == 1)

        source.release()
        await first.value
        await second.value

        #expect(store.inventory.packages.map(\.name) == ["wget"])
    }

    /// The request key M2-1 D6 introduced is kept, not replaced: the mark is an
    /// additional condition on joining, so repointing `brew` still forces its
    /// own acquisition even with no invalidation at all.
    @Test("The request key still governs joining alongside the mark")
    func theRequestKeyStillGovernsJoining() async {
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

        source.release()
        await first.value
        await second.value
    }

    // MARK: - Resetting mid-acquisition (D8c — II10 sc7)

    /// The third absorbed defect: `clear(to:)` bumped the ordinal but left the
    /// in-flight slot resident, so a refresh requested afterwards joined an
    /// acquisition whose answer the ordinal guard then discarded — and the
    /// inventory stayed empty for good.
    @Test("Resetting during an acquisition does not strand the inventory")
    func clearDuringAnAcquisitionDoesNotStrandTheSlot() async {
        let source = FakeInstalledPayloadSource([
            .formulae(["stale"]),
            .formulae(["wget", "curl"])
        ], gated: true)
        let store = InstalledStore(source: source)

        let stranded = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)

        // Detection reports brew absent while that acquisition is still open.
        await store.refresh(for: .absent)
        #expect(store.state == .brewAbsent(.notInstalled(.standard)))

        // Detection recovers, and the refresh is requested before the first
        // acquisition has settled.
        let recovery = Task {
            await store.refresh(for: .detected(TestInstallation.appleSilicon))
        }
        await source.waitForCalls(atLeast: 2)

        #expect(source.callCount == 2, "the recovery refresh joined the stranded acquisition")

        source.release()
        await stranded.value
        await recovery.value
        await settle()

        #expect(store.state == .loaded)
        #expect(store.inventory.packages.map(\.name) == ["curl", "wget"])
    }

    /// And the guard that made the strand survivable stays load-bearing: the
    /// pre-clear acquisition is still discarded, so `.brewAbsent` is never
    /// answered by data observed before it.
    @Test("A pre-clear acquisition never lands on top of the cleared state")
    func aPreClearAcquisitionIsDiscarded() async {
        let source = FakeInstalledPayloadSource([.formulae(["stale"])], gated: true)
        let store = InstalledStore(source: source)

        let stranded = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)

        await store.refresh(for: .absent)

        source.release()
        await stranded.value
        await settle()

        #expect(store.inventory.isEmpty)
        #expect(store.state == .brewAbsent(.notInstalled(.standard)))
    }
}
