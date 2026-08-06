import CellarTestSupport
import Foundation
import Testing

@testable import Catalog

@Suite("Catalog sync engine", .timeLimit(.minutes(1)))
struct SyncEngineTests {
    // MARK: - Acquisition through the seam (CS1)

    @Test("A sync succeeds with no brew present and asks each source exactly once")
    func syncNeedsNoBrewAndAsksEachSourceOnce() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget", "git"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        let result = await harness.engine.sync()

        // `Catalog` does not depend on `BrewProcess` at all, so "no brew process
        // was spawned" is a linker-level guarantee, not a runtime one. What the
        // test can prove is that every byte arrived through the seam.
        let snapshot = try #require(result.value)
        #expect(snapshot.packages.map(\.name).sorted() == ["git", "iterm2", "wget"])
        #expect(harness.source.requests(for: .formulae).count == 1)
        #expect(harness.source.requests(for: .casks).count == 1)
        // The two analytics endpoints are asked once each and are allowed to
        // fail; here they are unscripted, so they do.
        #expect(harness.source.requests(for: .analyticsFormula).count == 1)
        #expect(harness.source.requests(for: .analyticsCask).count == 1)
    }

    // MARK: - Conditional revalidation (CS2)

    @Test("A first sync carries no validators at all")
    func firstSyncIsUnconditional() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        _ = await harness.engine.sync()

        // Two payload resources plus the two analytics endpoints.
        #expect(harness.source.requests.count == 4)
        #expect(harness.source.requests.allSatisfy { ($0.validators?.isEmpty ?? true) })
    }

    @Test("Two unchanged sources read no body, write no snapshot, and still advance downloadedAt")
    func unchangedSourcesRevalidateOnly() async throws {
        let harness = try SyncHarness()
        harness.source.script(
            .payload(Payload.formulae(["wget"]), validators: ConditionalValidators(etag: "V1")),
            for: .formulae
        )
        harness.source.script(
            .payload(Payload.casks(["iterm2"]), validators: ConditionalValidators(etag: "C1")),
            for: .casks
        )
        _ = await harness.engine.sync()
        let firstDownloadedAt = try #require(
            try harness.store.loadState()?.sources[.formulae]?.downloadedAt
        )
        let payloadsAfterFirstSync = harness.source.deliveredPayloadCount

        harness.source.script(.notModified, for: .formulae)
        harness.source.script(.notModified, for: .casks)
        harness.time.advance(by: 3_600)

        let result = await harness.engine.sync()

        #expect(result.value != nil)
        #expect(harness.source.deliveredPayloadCount == payloadsAfterFirstSync)
        // The stored validators went back out on the wire.
        #expect(harness.source.requests(for: .formulae).last?.validators?.etag == "V1")

        let snapshot = try #require(try harness.store.loadSnapshot())
        #expect(snapshot.packages.map(\.name).sorted() == ["iterm2", "wget"])

        let state = try #require(try harness.store.loadState())
        #expect(state.sources[.formulae]?.downloadedAt == firstDownloadedAt.addingTimeInterval(3_600))
        #expect(state.sources[.formulae]?.validators.etag == "V1")
    }

    @Test("A changed payload replaces the snapshot and records the new validator verbatim")
    func changedPayloadRecordsNewValidators() async throws {
        let harness = try SyncHarness()
        harness.source.script(
            .payload(Payload.formulae(["wget"]), validators: ConditionalValidators(etag: "V1")),
            for: .formulae
        )
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()

        let rawLastModified = "Sat, 01 Aug 2026 17:17:26 GMT"
        harness.source.script(
            .payload(
                Payload.formulae(["wget", "curl"]),
                validators: ConditionalValidators(etag: "V2", lastModified: rawLastModified)
            ),
            for: .formulae
        )
        harness.source.script(.notModified, for: .casks)

        _ = await harness.engine.sync()

        let state = try #require(try harness.store.loadState())
        #expect(state.sources[.formulae]?.validators.etag == "V2")
        // Byte-for-byte: a DateFormatter round trip risks re-emitting a value the
        // origin no longer recognises, silently costing a 31 MB download.
        #expect(state.sources[.formulae]?.validators.lastModified == rawLastModified)

        let snapshot = try #require(try harness.store.loadSnapshot())
        #expect(snapshot.packages.map(\.name).sorted() == ["curl", "iterm2", "wget"])
    }

    @Test("A readable sidecar with an unreadable snapshot forces an unconditional re-download")
    func unreadableSnapshotDisablesRevalidation() async throws {
        let harness = try SyncHarness()
        harness.source.script(
            .payload(Payload.formulae(["wget"]), validators: ConditionalValidators(etag: "V1")),
            for: .formulae
        )
        harness.source.script(
            .payload(Payload.casks(["iterm2"]), validators: ConditionalValidators(etag: "C1")),
            for: .casks
        )
        _ = await harness.engine.sync()

        // The sidecar survives but the snapshot it certifies does not — the
        // crash-window state a 304 cannot rebuild from.
        try Data("not json".utf8).write(to: harness.store.snapshotURL)
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        let result = await harness.engine.sync()

        // The stored validators must NOT go out: with no readable snapshot a
        // revalidated 304 would persist an empty catalog as success.
        #expect(harness.source.requests(for: .formulae).last?.validators == nil)
        #expect(harness.source.requests(for: .casks).last?.validators == nil)
        let snapshot = try #require(result.value)
        #expect(snapshot.packages.map(\.name).sorted() == ["iterm2", "wget"])
        let persisted = try #require(try harness.store.loadSnapshot())
        #expect(persisted.packages.isEmpty == false)
    }

    // MARK: - Failure never erases the cache (CS4)

    @Test("A transport error keeps a large cached catalog answering", .heavyFixture)
    func transportErrorPreservesTheCache() async throws {
        let harness = try SyncHarness()
        let names = (0..<15_000).map { "pkg\($0)" }
        harness.source.script(.payload(Payload.formulae(names)), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()

        harness.source.script(.failure(.offline), for: .formulae)

        let result = await harness.engine.sync()

        #expect(result.error == .offline)
        let snapshot = try #require(try harness.store.loadSnapshot())
        #expect(snapshot.packages.count == 15_001)
    }

    @Test("503 is retried to success, 404 is asked once")
    func retryPolicyDistinguishesStatusCodes() async throws {
        let harness = try SyncHarness()
        harness.source.script(
            [.failure(.httpStatus(503)), .failure(.httpStatus(503)),
             .payload(Payload.formulae(["wget"]))],
            for: .formulae
        )
        harness.source.script(.failure(.httpStatus(404)), for: .casks)

        let result = await harness.engine.sync()

        #expect(harness.source.requests(for: .formulae).count == 3)
        #expect(harness.source.requests(for: .casks).count == 1)
        #expect(result.error == .httpStatus(404))
    }

    @Test("429 is retried like a 5xx")
    func tooManyRequestsIsRetried() async throws {
        let harness = try SyncHarness()
        harness.source.script(
            [.failure(.httpStatus(429)), .payload(Payload.formulae(["wget"]))],
            for: .formulae
        )
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        let result = await harness.engine.sync()

        #expect(harness.source.requests(for: .formulae).count == 2)
        #expect(result.value != nil)
    }

    @Test("A non-JSON body fails as malformed and leaves the snapshot untouched")
    func malformedBodyPreservesTheSnapshot() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()

        harness.source.script(.payload(Data("<!DOCTYPE html><html>nope".utf8)), for: .formulae)
        harness.source.script(.notModified, for: .casks)

        let result = await harness.engine.sync()

        #expect(result.error == .malformedPayload)
        let snapshot = try #require(try harness.store.loadSnapshot())
        #expect(snapshot.packages.map(\.name).sorted() == ["iterm2", "wget"])
        // Malformed is not retryable: one request, no backoff storm.
        #expect(harness.source.requests(for: .formulae).count == 2)
    }

    // MARK: - Staging lifecycle

    @Test("Cancellation mid-sync reports cancelled and purges staging")
    func cancellationPurgesStaging() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.source.onFetch { try? await Task.sleep(for: .milliseconds(80)) }

        let running = Task { await harness.engine.sync() }
        await TestPoll.until(harness.source.requests.isEmpty == false)
        await harness.engine.cancel()
        let result = await running.value

        #expect(result.error == .cancelled)
        #expect(
            FileManager.default.fileExists(atPath: harness.store.stagingURL.path) == false,
            "staging survived a cancelled sync"
        )
    }

    @Test("Staging is purged after a success and after a failure")
    func stagingIsPurgedOnEveryOutcome() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        _ = await harness.engine.sync()
        #expect(FileManager.default.fileExists(atPath: harness.store.stagingURL.path) == false)

        harness.source.script(.failure(.offline), for: .formulae)
        _ = await harness.engine.sync()
        #expect(FileManager.default.fileExists(atPath: harness.store.stagingURL.path) == false)
    }

    // MARK: - Observable status (CS8)

    @Test("A cold launch answers with no cache while the status reports progress")
    func coldLaunchIsNonBlocking() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.source.onFetch { try? await Task.sleep(for: .milliseconds(60)) }

        #expect(try harness.store.loadSnapshot() == nil)

        let running = Task { await harness.engine.sync() }
        await TestPoll.until(harness.source.requests.isEmpty == false)

        // Answering "what is the catalog right now" must not wait for the sync.
        let duringSync = await harness.engine.status
        #expect(duringSync == .downloading(fractionCompleted: nil) || duringSync == .decoding)

        let result = await running.value
        let snapshot = try #require(result.value)
        #expect(snapshot.packages.count == 2)

        let finalStatus = await harness.engine.status
        guard case .succeeded(let instant) = finalStatus else {
            Issue.record("expected succeeded, got \(finalStatus)")
            return
        }
        #expect(instant == harness.time.now)
    }

    @Test("A failed first sync is observable and throws nothing")
    func failedFirstSyncIsObservable() async throws {
        let harness = try SyncHarness()
        harness.source.script(.failure(.offline), for: .formulae)

        let result = await harness.engine.sync()

        #expect(result.error == .offline)
        #expect(await harness.engine.status == .failed(.offline))
        #expect(try harness.store.loadSnapshot() == nil)
    }

    // MARK: - The newness sidecars (CS-A1, CS-A2)

    @Test("A sync that publishes a new snapshot writes arrivals before the roster")
    func newSnapshotWritesArrivalsBeforeTheRoster() async throws {
        let harness = try SyncHarness(recording: true)
        let recorder = try #require(harness.recorder)
        harness.source.script(.payload(Payload.formulae(["wget", "git"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        let result = await harness.engine.sync()

        #expect(result.value != nil)
        // The crash-order choice, stated as an ordering: a crash between the two
        // costs a repeated arrival that earliest-`firstSeenAt` deduplicates,
        // while the reverse order marks a package seen with no arrival ever
        // written and loses it permanently.
        #expect(
            recorder.publishedPaths == [
                "catalog.json",
                "catalog-state.json",
                "catalog-arrivals.json",
                "catalog-roster.json"
            ]
        )
        // The first sync is the seeding pass, so the roster is full and the
        // arrivals log is empty (D5).
        let roster = try #require(harness.store.loadRoster())
        #expect(roster.formulae == ["git", "wget"])
        #expect(roster.casks == ["iterm2"])
        #expect(harness.store.loadArrivals()?.arrivals.isEmpty == true)
    }

    @Test("A second sync records only the package the roster had not seen")
    func secondSyncRecordsOnlyTheUnseenPackage() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()

        // A genuinely changed payload, so this is the new-snapshot path.
        harness.source.script(.payload(Payload.formulae(["wget", "newpkg"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.time.advance(by: 3_600)
        _ = await harness.engine.sync()

        let arrivals = try #require(harness.store.loadArrivals())
        #expect(arrivals.arrivals.map(\.name) == ["newpkg"])
        #expect(arrivals.arrivals.first?.firstSeenAt == harness.time.now)
        #expect(harness.store.loadRoster()?.formulae == ["newpkg", "wget"])
    }

    @Test("A fully revalidated sync writes neither sidecar and records no arrival")
    func revalidatedSyncLeavesBothSidecarsUntouched() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()

        let rosterBefore = try Data(contentsOf: harness.store.rosterURL)
        let arrivalsBefore = try Data(contentsOf: harness.store.arrivalsURL)

        // Everything revalidates: the packages are identical, so diffing would
        // be a guaranteed no-op costing a roster read and a 16k set compare.
        harness.source.script(.notModified, for: .formulae)
        harness.source.script(.notModified, for: .casks)
        harness.time.advance(by: 90_000)
        let result = await harness.engine.sync()

        #expect(result.value != nil)
        #expect(try Data(contentsOf: harness.store.rosterURL) == rosterBefore)
        #expect(try Data(contentsOf: harness.store.arrivalsURL) == arrivalsBefore)
        #expect(harness.store.loadArrivals()?.arrivals.isEmpty == true)
    }

    @Test("A roster write failure leaves the sync successful and the snapshot served")
    func rosterWriteFailureDoesNotFailTheSync() async throws {
        let harness = try SyncHarness(recording: true)
        let recorder = try #require(harness.recorder)
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        recorder.failReplacements(of: harness.store.rosterURL)

        let result = await harness.engine.sync()

        // Newness is decoration. A roster that cannot be written costs newness
        // for one sync; it must never cost the catalog that already arrived.
        #expect(result.value != nil)
        #expect(await harness.engine.status.isBusy == false)
        #expect(try harness.store.loadSnapshot()?.packages.isEmpty == false)
        #expect(try harness.store.loadState() != nil)
        #expect(harness.store.loadRoster() == nil)
    }

    @Test("An arrivals write failure leaves the sync successful and the snapshot served")
    func arrivalsWriteFailureDoesNotFailTheSync() async throws {
        let harness = try SyncHarness(recording: true)
        let recorder = try #require(harness.recorder)
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        recorder.failReplacements(of: harness.store.arrivalsURL)

        let result = await harness.engine.sync()

        #expect(result.value != nil)
        #expect(try harness.store.loadSnapshot()?.packages.isEmpty == false)
        #expect(try harness.store.loadState() != nil)
        // Arrivals is written first, so its failure costs the roster too — and
        // still not the sync.
        #expect(harness.store.loadArrivals() == nil)
    }

    @Test("The engine serves the arrivals log already pruned to the window")
    func engineServesPrunedArrivals() async throws {
        let harness = try SyncHarness()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try FileManager.default.createDirectory(
            at: harness.directory, withIntermediateDirectories: true
        )
        try encoder.encode(
            PackageArrivalsLog(arrivals: [
                PackageArrival(
                    kind: .formula,
                    name: "stale",
                    firstSeenAt: harness.time.now.addingTimeInterval(-31 * 24 * 3_600)
                ),
                PackageArrival(
                    kind: .formula,
                    name: "fresh",
                    firstSeenAt: harness.time.now.addingTimeInterval(-2 * 24 * 3_600)
                )
            ])
        )
        .write(to: harness.store.arrivalsURL)

        // Read-time pruning, with no sync having run: the 30-day rule holds
        // regardless of sync cadence.
        let served = await harness.engine.arrivals()

        #expect(served?.arrivals.map(\.name) == ["fresh"])
    }

    @Test("An expired arrival is removed from the file by the next write")
    func expiredArrivalIsGoneFromTheFileAfterTheNextWrite() async throws {
        // The **write** half of CS-A2 sc3. Read-time pruning above makes the
        // 30-day answer true; it does nothing to bound the file, because it
        // never touches the bytes. Only a write can do that, so this is the
        // half that has to be observed against the file on disk rather than
        // against the projection — a log that grew forever would satisfy every
        // read-side assertion in this suite.
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        // A first sync seeds the roster, so the sync below takes the diffing
        // path rather than the seeding one.
        _ = await harness.engine.sync()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(
            PackageArrivalsLog(arrivals: [
                PackageArrival(
                    kind: .formula,
                    name: "stalepkg",
                    firstSeenAt: harness.time.now.addingTimeInterval(-31 * 24 * 3_600)
                ),
                PackageArrival(
                    kind: .formula,
                    name: "freshpkg",
                    firstSeenAt: harness.time.now.addingTimeInterval(-2 * 24 * 3_600)
                )
            ])
        )
        .write(to: harness.store.arrivalsURL)

        // The expired entry really is in the persisted bytes beforehand, so the
        // assertion below is about a removal rather than about an absence that
        // was always there.
        let before = try #require(
            String(data: try Data(contentsOf: harness.store.arrivalsURL), encoding: .utf8)
        )
        #expect(before.contains("stalepkg"))

        // A genuinely changed payload, so this sync materializes a new snapshot
        // and therefore writes the sidecars.
        harness.source.script(.payload(Payload.formulae(["wget", "newpkg"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.time.advance(by: 3_600)
        #expect(await harness.engine.sync().value != nil)

        // Re-read the file, not the projection.
        let persisted = try Data(contentsOf: harness.store.arrivalsURL)
        let after = try #require(String(data: persisted, encoding: .utf8))
        #expect(after.contains("stalepkg") == false, "the expired arrival survived the write")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let reloaded = try decoder.decode(PackageArrivalsLog.self, from: persisted)
        // The entry inside the window survives, and the genuinely new package
        // was recorded — so the write pruned rather than simply truncating.
        #expect(reloaded.arrivals.map(\.name).sorted() == ["freshpkg", "newpkg"])
        #expect(reloaded.arrivals.contains { $0.name == "stalepkg" } == false)
    }
}

// MARK: - Harness

/// A sync engine wired to a real temp directory, a scripted source, a manually
/// advanced clock and a manually advanced wall clock.
struct SyncHarness {
    let directory: URL
    let store: CatalogFileStore
    let source: FakeCatalogSource
    let clock: TestClock
    let time: FakeTimeSource
    let engine: CatalogSyncEngine
    /// Non-nil when the store was wired to the in-memory recorder instead of the
    /// real temp directory — the seam an ordering assertion needs.
    let recorder: FakeCatalogFileSystem?

    init(
        policy: CatalogRefreshPolicy = CatalogRefreshPolicy(backoff: .zero),
        recording: Bool = false
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        recorder = recording ? FakeCatalogFileSystem() : nil
        store = if let recorder {
            CatalogFileStore(directory: directory, fileSystem: recorder)
        } else {
            CatalogFileStore(directory: directory)
        }
        source = FakeCatalogSource()
        clock = TestClock()
        time = FakeTimeSource()
        engine = CatalogSyncEngine(
            store: store,
            source: source,
            clock: clock,
            timeSource: time,
            policy: policy
        )
    }

    /// A second engine over the same directory, source and clocks.
    ///
    /// The event stream buffers, so a store attached to an engine that already
    /// synced would replay that snapshot. A launch has to start clean.
    func freshEngine(policy: CatalogRefreshPolicy = CatalogRefreshPolicy(backoff: .zero))
        -> CatalogSyncEngine {
        CatalogSyncEngine(
            store: store,
            source: source,
            clock: clock,
            timeSource: time,
            policy: policy
        )
    }

    /// Overwrites `catalog.json` with a well-formed, current-schema snapshot
    /// holding zero packages, leaving the sidecar and its validators intact.
    ///
    /// The exact on-disk state defect #7 describes: readable, certified by
    /// stored validators, and useless.
    func poisonSnapshot() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let poisoned = CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            skippedRecordCount: 0,
            packages: []
        )
        try encoder.encode(poisoned).write(to: store.snapshotURL)
    }
}

/// Minimal payload bodies in the published shape.
enum Payload {
    static func formulae(_ names: [String]) -> Data {
        let records = names.map { name in
            """
            {"name":"\(name)","tap":"homebrew/core","desc":"the \(name) package",\
            "versions":{"stable":"1.0.0"},"dependencies":[],"build_dependencies":[]}
            """
        }
        return Data("[\(records.joined(separator: ","))]".utf8)
    }

    static func casks(_ tokens: [String]) -> Data {
        let records = tokens.map { token in
            """
            {"token":"\(token)","name":["\(token.capitalized)"],"tap":"homebrew/cask",\
            "desc":"the \(token) cask","version":"1.0.0"}
            """
        }
        return Data("[\(records.joined(separator: ","))]".utf8)
    }
}

extension Result {
    var value: Success? { try? get() }

    var error: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
