import Foundation
import Testing

@testable import Catalog

@Suite("Catalog sync engine", .timeLimit(.minutes(1)))
struct SyncEngineTests {
    /// Lets every pending continuation run without depending on wall-clock time.
    static func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

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

    @Test("A transport error keeps a large cached catalog answering")
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

    // MARK: - Single flight (CSA2)

    @Test("Two callers waiting on one gated sync perform exactly one acquisition")
    func concurrentCallersCoalesceOntoOneSync() async throws {
        let harness = try SyncHarness()
        let gate = Gate()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.source.onFetch { await gate.wait() }

        let first = Task { await harness.engine.sync() }
        await gate.waitForWaiters(atLeast: 1)
        let second = Task { await harness.engine.sync() }
        await Self.settle()

        // A second acquisition here would mean the join never happened.
        #expect(harness.source.requests(for: .formulae).count == 1)

        gate.open()
        let firstResult = await first.value
        let secondResult = await second.value

        #expect(firstResult.value?.packages.map(\.name).sorted() == ["iterm2", "wget"])
        #expect(secondResult.value?.packages.map(\.name).sorted() == ["iterm2", "wget"])
        #expect(harness.source.requests(for: .formulae).count == 1)
    }

    @Test("A joiner resuming from a settled sync starts fresh work rather than re-reading it")
    func settledSyncDoesNotAnswerALaterCaller() async throws {
        let harness = try SyncHarness()
        let gate = Gate()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.source.onFetch { await gate.wait() }

        // The joiner asks again the instant its join resumes — the exact window
        // in which the settled task is still parked in the coalescing slot.
        let first = Task { await harness.engine.sync() }
        await gate.waitForWaiters(atLeast: 1)
        let second = Task { () -> Result<CatalogSnapshot, CatalogSyncError> in
            _ = await harness.engine.sync()
            return await harness.engine.sync()
        }
        await Self.settle()

        // P2: what the *second* acquisition must see.
        harness.source.script(.payload(Payload.formulae(["wget", "curl"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        gate.open()

        _ = await first.value
        let followUp = await second.value

        #expect(harness.source.requests(for: .formulae).count == 2)
        #expect(followUp.value?.packages.map(\.name).sorted() == ["curl", "iterm2", "wget"])
    }

    @Test("A caller arriving after a cancellation starts fresh work instead of inheriting it")
    func cancelledSyncDoesNotAnswerALaterCaller() async throws {
        let harness = try SyncHarness()
        let gate = Gate()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.source.onFetch { await gate.wait() }

        let cancelled = Task { await harness.engine.sync() }
        await gate.waitForWaiters(atLeast: 1)
        await harness.engine.cancel()

        // What the fresh work must see, so a pass cannot come from re-reading
        // whatever the cancelled attempt had already staged.
        harness.source.script(.payload(Payload.formulae(["wget", "curl"])), for: .formulae)
        let successor = Task { await harness.engine.sync() }
        await Self.settle()
        gate.open()

        #expect(await cancelled.value.error == .cancelled)

        let successorResult = await successor.value
        #expect(successorResult.error != .cancelled)
        #expect(successorResult.value?.packages.map(\.name).sorted() == ["curl", "iterm2", "wget"])
    }

    @Test("The cancelled run finishes purging staging before its successor stages anything")
    func cancelledRunUnwindsBeforeItsSuccessorStages() async throws {
        let harness = try SyncHarness(recording: true)
        let recorder = try #require(harness.recorder)
        let gate = Gate()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.source.onFetch { await gate.wait() }

        let cancelled = Task { await harness.engine.sync() }
        await gate.waitForWaiters(atLeast: 1)
        await harness.engine.cancel()
        let successor = Task { await harness.engine.sync() }
        await Self.settle()
        gate.open()

        _ = await cancelled.value
        _ = await successor.value

        // Interleaved staging would read create, create, purge, purge — and the
        // cancelled run's `defer { purgeStaging() }` would take the successor's
        // download with it.
        #expect(
            recorder.stagingLifecycle(at: harness.store.stagingURL) == [
                .created, .purged, .created, .purged,
            ]
        )
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
