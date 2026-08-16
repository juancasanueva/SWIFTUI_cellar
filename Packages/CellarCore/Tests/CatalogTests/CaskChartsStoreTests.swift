import Foundation
import Synchronization
import Testing

@testable import Catalog

/// The Top Charts data seam: lazy per-period fetch, memory-then-disk caching,
/// the fallback commit on failure, and the request guard that drops a stale
/// response when the user switches periods faster than the network answers.
@Suite("Cask charts store")
@MainActor
struct CaskChartsStoreTests {
    /// The same fixed clock the browse projection suite uses.
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - The window that needs no fetch

    @Test("days365 commits without ever calling the source")
    func days365CommitsWithoutFetching() async {
        let source = FakeChartsSource(counts: [.days30: ["iterm2": 5]])
        let store = Self.store(source: source)

        await store.select(.days365)

        #expect(store.period == .days365)
        #expect(store.isLoading == false)
        // The catalog already carries every 365d count on the packages; the
        // store never fetches it and never stores it.
        #expect(source.totalFetchCount == 0)
        #expect(store.countsByPeriod[.days365] == nil)
    }

    // MARK: - Memory cache

    @Test("A period is fetched once, then served from memory")
    func fetchesOncePerPeriodThenServesMemory() async {
        let source = FakeChartsSource(counts: [
            .days30: ["iterm2": 5],
            .days90: ["arc": 9]
        ])
        let store = Self.store(source: source)

        await store.select(.days30)
        #expect(store.period == .days30)
        #expect(store.countsByPeriod[.days30] == ["iterm2": 5])

        await store.select(.days90)
        await store.select(.days30)

        #expect(store.period == .days30)
        #expect(source.fetchCount(.days30) == 1)
        #expect(source.fetchCount(.days90) == 1)
    }

    // MARK: - Failure fallback

    @Test("A failed fetch falls back to the current period when it has data")
    func failureFallsBackToTheCurrentPeriodWithData() async {
        let source = FakeChartsSource(
            counts: [.days30: ["iterm2": 5]],
            failing: [.days90]
        )
        let store = Self.store(source: source)
        await store.select(.days30)

        await store.select(.days90)

        #expect(store.period == .days30)
        #expect(store.isLoading == false)
        #expect(store.countsByPeriod[.days90] == nil)
    }

    @Test("A failed fetch with nothing cached falls back to days365")
    func failureFallsBackToDays365WithoutData() async {
        let source = FakeChartsSource(failing: [.days30])
        let store = Self.store(source: source)

        await store.select(.days30)

        #expect(store.period == .days365)
        #expect(store.isLoading == false)
    }

    // MARK: - Racing selections

    @Test("Racing selections keep only the latest; the stale response is dropped whole")
    func racingSelectionsKeepOnlyTheLatest() async {
        let gate = Gate()
        let source = FakeChartsSource(
            counts: [.days30: ["slow": 1], .days90: ["fast": 2]],
            gates: [.days30: gate]
        )
        let store = Self.store(source: source)

        // The slow selection is provably *inside* the fetch before the fast one
        // starts, so the drop is a decision rather than a lucky ordering.
        let slow = Task { await store.select(.days30) }
        await gate.waitForWaiters(atLeast: 1)
        await store.select(.days90)
        #expect(store.period == .days90)

        gate.open()
        await slow.value

        // Dropped whole: neither the commit nor the counts survive.
        #expect(store.period == .days90)
        #expect(store.countsByPeriod[.days30] == nil)
        #expect(store.isLoading == false)
    }

    @Test("Selecting days365 mid-flight drops the in-flight response and stops loading")
    func selectingDays365MidFlightDropsTheResponse() async {
        let gate = Gate()
        let source = FakeChartsSource(
            counts: [.days30: ["slow": 1]],
            gates: [.days30: gate]
        )
        let store = Self.store(source: source)

        let slow = Task { await store.select(.days30) }
        await gate.waitForWaiters(atLeast: 1)
        #expect(store.isLoading)

        await store.select(.days365)
        #expect(store.isLoading == false)

        gate.open()
        await slow.value

        #expect(store.period == .days365)
        #expect(store.countsByPeriod[.days30] == nil)
    }

    // MARK: - Disk cache

    @Test("The cache round-trips through the injected directory")
    func cacheRoundTripsThroughTheInjectedDirectory() async {
        let directory = Self.temporaryDirectory()
        let writer = Self.store(
            source: FakeChartsSource(counts: [.days30: ["iterm2": 7]]),
            directory: directory
        )
        await writer.select(.days30)

        // A fresh launch ten minutes later, with a source that would fail: the
        // answer has to come off disk or not at all.
        let reader = Self.store(
            source: FakeChartsSource(failing: [.days30]),
            directory: directory,
            now: Self.t0.addingTimeInterval(600)
        )
        await reader.select(.days30)

        #expect(reader.period == .days30)
        #expect(reader.countsByPeriod[.days30] == ["iterm2": 7])
    }

    @Test("A cached period past its TTL is a miss, and the source is asked again")
    func ttlExpiryRefetches() async {
        let directory = Self.temporaryDirectory()
        let writer = Self.store(
            source: FakeChartsSource(counts: [.days30: ["stale": 1]]),
            directory: directory
        )
        await writer.select(.days30)

        let fresh = FakeChartsSource(counts: [.days30: ["fresh": 2]])
        let reader = Self.store(
            source: fresh,
            directory: directory,
            now: Self.t0.addingTimeInterval(CaskChartsStore.timeToLive + 1)
        )
        await reader.select(.days30)

        #expect(fresh.fetchCount(.days30) == 1)
        #expect(reader.countsByPeriod[.days30] == ["fresh": 2])
        #expect(reader.period == .days30)
    }

    @Test("A wrong schema version is a clean miss, never an error")
    func wrongSchemaVersionIsACleanMiss() async throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let alien = #"{"schemaVersion":99,"entries":{"30d":{"counts":{"ghost":1},"fetchedAt":"2027-01-15T08:00:00Z"}}}"#
        try Data(alien.utf8).write(
            to: directory.appendingPathComponent(CaskChartsStore.cacheFileName)
        )

        let source = FakeChartsSource(counts: [.days30: ["iterm2": 3]])
        let store = Self.store(source: source, directory: directory)
        await store.select(.days30)

        #expect(store.period == .days30)
        #expect(store.countsByPeriod[.days30] == ["iterm2": 3])
        #expect(source.fetchCount(.days30) == 1)
    }

    @Test("Byte-corrupt cache contents are a miss, never an error")
    func corruptCacheIsACleanMiss() async throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(
            to: directory.appendingPathComponent(CaskChartsStore.cacheFileName)
        )

        let source = FakeChartsSource(counts: [.days90: ["arc": 4]])
        let store = Self.store(source: source, directory: directory)
        await store.select(.days90)

        #expect(store.period == .days90)
        #expect(store.countsByPeriod[.days90] == ["arc": 4])
    }

    // MARK: - Helpers

    static func store(
        source: FakeChartsSource,
        directory: URL = temporaryDirectory(),
        now: Date = t0
    ) -> CaskChartsStore {
        CaskChartsStore(source: source, directory: directory, now: { now })
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cask-charts-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

/// A charts source whose answers, failures and timing the test owns.
final class FakeChartsSource: CaskChartsSource, Sendable {
    private let counts: [CaskChartsPeriod: [String: Int]]
    private let failing: Set<CaskChartsPeriod>
    private let gates: [CaskChartsPeriod: Gate]
    private let calls = Mutex<[CaskChartsPeriod]>([])

    init(
        counts: [CaskChartsPeriod: [String: Int]] = [:],
        failing: Set<CaskChartsPeriod> = [],
        gates: [CaskChartsPeriod: Gate] = [:]
    ) {
        self.counts = counts
        self.failing = failing
        self.gates = gates
    }

    var totalFetchCount: Int { calls.withLock { $0.count } }

    func fetchCount(_ period: CaskChartsPeriod) -> Int {
        calls.withLock { $0.count { $0 == period } }
    }

    func fetchCounts(period: CaskChartsPeriod) async throws -> [String: Int] {
        calls.withLock { $0.append(period) }
        if let gate = gates[period] { await gate.wait() }
        if failing.contains(period) { throw CatalogSyncError.offline }
        return counts[period] ?? [:]
    }
}
