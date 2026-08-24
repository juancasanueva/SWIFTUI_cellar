import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// `package-trust` PT2 :107-112 — the grant store keeps the tap store's
/// discipline, because a second read that does not coalesce, does not retain a
/// last good answer, and adopts whatever lands last would be a worse citizen
/// than the one Cellar already ships.
@MainActor
@Suite("Per-package trust store freshness", .timeLimit(.minutes(1)))
struct TrustGrantStoreTests {
    // MARK: - PT2 :134-139 — concurrent refreshes coalesce into one spawn

    @Test("Concurrent refreshes coalesce into one spawn")
    func concurrentRefreshesCoalesceIntoOneSpawn() async {
        let source = FakeTrustGrantPayloadSource([
            .payload("{\"formulae\":[\"acme/tools/widget\"],\"casks\":[]}"),
            .payload("{\"formulae\":[\"other/tools/desk\"],\"casks\":[]}")
        ], gated: true)
        let store = TrustGrantStore(source: source)

        // One in flight, three more asked for while it is.
        let requests = (0..<4).map { _ in
            Task { await store.refresh(using: TestInstallation.appleSilicon) }
        }
        await source.waitForCalls(atLeast: 1)
        source.release(call: 0)
        for request in requests { await request.value }

        #expect(source.callCount == 1, "the grant read spawned \(source.callCount) times for one answer")
        #expect(store.grants.ledger?.formulae == ["acme/tools/widget"])
        #expect(store.state == .loaded)

        // …and all four requests observed that same one report, which is the
        // half of coalescing that matters to a caller.
        #expect(store.grants == .granted(TrustGrantLedger(
            formulae: ["acme/tools/widget"],
            casks: [],
            declaredNamespaces: ["formulae", "casks"]
        )))

        // Triangulated: `invalidate()` defeats coalescing, so a mutation's
        // terminal cannot be answered from an answer taken before it ran.
        store.invalidate()
        let later = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 2)
        source.release(call: 1)
        await later.value

        #expect(source.callCount == 2)
        #expect(store.grants.ledger?.formulae == ["other/tools/desk"])
    }

    // MARK: - PT2 :141-147 — a failed refresh keeps the last good report

    /// **R4 again, from the other side.** Replacing a good report with an empty
    /// one on failure would make a count disappear for a reason that has nothing
    /// to do with what Homebrew grants.
    @Test("A failed refresh keeps the last good report")
    func aFailedRefreshKeepsTheLastGoodReport() async {
        let source = FakeTrustGrantPayloadSource([
            .payload("{\"formulae\":[\"acme/tools/widget\"],\"casks\":[\"acme/tools/desk\"]}"),
            .failure(.commandFailed(status: 1, message: "busy"))
        ])
        let store = TrustGrantStore(source: source)

        await store.refresh(using: TestInstallation.appleSilicon)
        let good = store.grants
        #expect(good.ledger?.entryCount == 2)

        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(store.grants == good, "a failure replaced the last good report")
        #expect(store.grants.entryCount == 2)
        #expect(store.state == .failed(.commandFailed(status: 1, message: "busy")))
        #expect(store.grants != .noGrants)
        #expect(store.grants != .unreported)
        #expect(source.callCount == 2)

        // A **first-ever** failure has no last good answer to keep, and the
        // honest value there is `unreported` — not zero.
        let cold = TrustGrantStore(source: FakeTrustGrantPayloadSource([
            .failure(.commandFailed(status: 1, message: "Error: Unknown command: trust"))
        ]))
        await cold.refresh(using: TestInstallation.appleSilicon)
        #expect(cold.grants == .unreported)
        #expect(cold.grants.entryCount == nil)
    }

    // MARK: - PT2 :149-154 — a stale answer is not adopted over a newer one

    @Test("A stale answer is not adopted over a newer one")
    func aStaleAnswerIsNotAdoptedOverANewerOne() async {
        let source = FakeTrustGrantPayloadSource([
            .payload("{\"formulae\":[\"old/tools/widget\"],\"casks\":[]}"),
            .payload("{\"formulae\":[\"new/tools/widget\"],\"casks\":[]}")
        ], gated: true)
        let store = TrustGrantStore(source: source)

        let old = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)
        store.invalidate()
        let new = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 2)

        // The newer answer lands first; the older one arrives afterwards.
        source.release(call: 1)
        await new.value
        source.release(call: 0)
        await old.value

        #expect(source.callCount == 2)
        #expect(store.grants.ledger?.formulae == ["new/tools/widget"])
        #expect(store.grants.ledger?.formulae != ["old/tools/widget"])
    }
}
