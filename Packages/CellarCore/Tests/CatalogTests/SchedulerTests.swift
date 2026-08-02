import CellarTestSupport
import Foundation
import Testing

@testable import Catalog

/// The refresh schedule, exercised entirely on a manually advanced clock and a
/// manually advanced wall clock — no test in this suite waits on real time.
@Suite("Refresh scheduling")
struct SchedulerTests {
    static let twoHours: TimeInterval = 2 * 60 * 60
    static let thirtyHours: TimeInterval = 30 * 60 * 60

    @Test("A catalog younger than a day issues no request on load")
    func freshCatalogDoesNotSyncOnLoad() async throws {
        let harness = try await Self.synced()
        let requestsAfterSeeding = harness.source.requests.count
        harness.time.advance(by: Self.twoHours)

        let loop = Task { await harness.engine.runRefreshLoop() }
        defer { loop.cancel() }
        // The loop only sleeps once it has evaluated staleness.
        await harness.clock.waitForSleepers()

        #expect(harness.source.requests.count == requestsAfterSeeding)
        #expect(await harness.engine.isStale() == false)
    }

    @Test("A stale catalog refreshes in the background while still serving the cache")
    func staleCatalogRefreshesSilently() async throws {
        let harness = try await Self.synced()
        harness.time.advance(by: Self.thirtyHours)
        harness.source.script(.payload(Payload.formulae(["wget", "curl"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.source.onFetch { try? await Task.sleep(for: .milliseconds(60)) }

        #expect(await harness.engine.isStale())

        let loop = Task { await harness.engine.runRefreshLoop() }
        defer { loop.cancel() }
        await TestPoll.until(harness.source.requests.count > 2)

        // Mid-flight the old records are still the answer.
        let duringSync = await harness.engine.cachedSnapshot()
        #expect(duringSync?.packages.map(\.name).sorted() == ["iterm2", "wget"])

        await TestPoll.until(
            ((try? harness.store.loadSnapshot())??.packages.count ?? 0) == 3
        )
        let afterSync = try #require(try harness.store.loadSnapshot())
        #expect(afterSync.packages.map(\.name).sorted() == ["curl", "iterm2", "wget"])
    }

    @Test("A manual refresh syncs regardless of age")
    func manualRefreshIgnoresAge() async throws {
        let harness = try await Self.synced()
        harness.time.advance(by: Self.twoHours)
        let before = harness.source.requests(for: .formulae).count

        _ = await harness.engine.sync()

        #expect(harness.source.requests(for: .formulae).count == before + 1)
    }

    @Test("A second manual refresh joins the one in flight instead of starting another")
    func manualRefreshIsSingleFlight() async throws {
        let harness = try await Self.synced()
        let before = harness.source.requests(for: .formulae).count
        harness.source.onFetch { try? await Task.sleep(for: .milliseconds(80)) }

        let first = Task { await harness.engine.sync() }
        await TestPoll.until(harness.source.requests(for: .formulae).count == before + 1)
        let second = Task { await harness.engine.sync() }

        let firstResult = await first.value
        let secondResult = await second.value

        #expect(firstResult.value != nil)
        #expect(secondResult.value != nil)
        // One extra request, not two: the second caller joined.
        #expect(harness.source.requests(for: .formulae).count == before + 1)
    }

    @Test("Thirty hours of system sleep across a paused clock triggers exactly one sync")
    func wakeFromSleepSyncsOnce() async throws {
        let harness = try await Self.synced()
        let before = harness.source.requests(for: .formulae).count

        let loop = Task { await harness.engine.runRefreshLoop() }
        defer { loop.cancel() }
        await harness.clock.waitForSleepers()

        // The lid was closed for 30 h: wall-clock time moved, the monotonic
        // clock the loop sleeps on did not (design D5).
        harness.time.advance(by: Self.thirtyHours)
        await harness.clock.advance(by: .seconds(15 * 60))
        await TestPoll.until(harness.source.requests(for: .formulae).count == before + 1)

        // Now fresh again: further poll ticks must stay silent.
        for _ in 0..<3 {
            await harness.clock.waitForSleepers()
            await harness.clock.advance(by: .seconds(15 * 60))
        }
        await harness.clock.waitForSleepers()

        #expect(harness.source.requests(for: .formulae).count == before + 1)
        #expect(await harness.engine.isStale() == false)
    }

    // MARK: - Helpers

    /// A harness whose store already holds a snapshot downloaded "now".
    static func synced() async throws -> SyncHarness {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        let result = await harness.engine.sync()
        #expect(result.value != nil)
        harness.source.script(.notModified, for: .formulae)
        harness.source.script(.notModified, for: .casks)
        return harness
    }
}
