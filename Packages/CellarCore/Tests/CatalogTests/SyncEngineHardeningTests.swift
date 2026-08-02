import Foundation
import Testing

@testable import Catalog

/// The invariants `m2-catalog-hardening` adds to the sync engine: one identity
/// per materialization, a join only onto work genuinely in flight, and a
/// zero-package catalog refused at every end.
///
/// Split from `SyncEngineTests` so neither file outgrows the project's limits;
/// both share `SyncHarness`.
@Suite("Catalog sync engine hardening", .serialized, .timeLimit(.minutes(1)))
struct SyncEngineHardeningTests {
    /// Lets every pending continuation run without depending on wall-clock time.
    static func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    // MARK: - Snapshot identity (D2)

    @Test("The same file on disk keeps one identity across reads and revalidations")
    func diskRevisionIsPinnedToTheFile() async throws {
        let harness = try SyncHarness()
        harness.source.script(
            .payload(Payload.formulae(["wget"]), validators: ConditionalValidators(etag: "V1")),
            for: .formulae
        )
        harness.source.script(
            .payload(Payload.casks(["iterm2"]), validators: ConditionalValidators(etag: "C1")),
            for: .casks
        )
        let persisted = try #require(await harness.engine.sync().value)

        let firstRead = try #require(await harness.engine.cachedSnapshot())
        let secondRead = try #require(await harness.engine.cachedSnapshot())
        #expect(firstRead.revision == secondRead.revision)
        #expect(firstRead.revision == persisted.revision)

        // A 304-only sync re-emits the catalog already on disk. Without the pin
        // the 15-minute poll would hand out a fresh identity every time and
        // rebuild a 16k-record index forever.
        harness.source.script(.notModified, for: .formulae)
        harness.source.script(.notModified, for: .casks)
        harness.time.advance(by: 3_600)

        let revalidated = try #require(await harness.engine.sync().value)

        #expect(revalidated.revision == persisted.revision)
        #expect(revalidated.packages.map(\.name).sorted() == ["iterm2", "wget"])
    }

    @Test("A changed payload is a new identity")
    func changedPayloadTakesAFreshRevision() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        let first = try #require(await harness.engine.sync().value)

        harness.source.script(.payload(Payload.formulae(["wget", "curl"])), for: .formulae)
        harness.source.script(.notModified, for: .casks)
        let second = try #require(await harness.engine.sync().value)

        #expect(second.revision != first.revision)
        #expect(try #require(await harness.engine.cachedSnapshot()).revision == second.revision)
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
                .created, .purged, .created, .purged
            ]
        )
    }

    // MARK: - Degenerate payloads (CSA3, CSA4)

    @Test("A degenerate payload is refused and the last good catalog survives", .heavyFixture)
    func degeneratePayloadIsRefused() async throws {
        let harness = try SyncHarness(recording: true)
        let recorder = try #require(harness.recorder)
        let names = (0..<15_000).map { "pkg\($0)" }
        harness.source.script(.payload(Payload.formulae(names)), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()
        let writesBefore = recorder.publishedPaths

        // Well-formed JSON, zero usable records.
        harness.source.script(.payload(Payload.formulae([])), for: .formulae)
        harness.source.script(.notModified, for: .casks)

        let result = await harness.engine.sync()

        #expect(result.error == .malformedPayload)
        #expect(await harness.engine.status == .failed(.malformedPayload))
        #expect(recorder.publishedPaths == writesBefore, "the refused sync wrote to disk")
        let persisted = try #require(try harness.store.loadSnapshot())
        #expect(persisted.packages.count == 15_001)
    }

    @Test("A one-package catalog is not degenerate")
    func onePackageCatalogPersists() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.notModified, for: .casks)

        let result = await harness.engine.sync()

        // The threshold is exactly zero packages: no plausibility floor.
        #expect(result.value?.packages.map(\.name) == ["wget"])
        #expect(try harness.store.loadSnapshot()?.packages.map(\.name) == ["wget"])
    }

    @Test("An unchanged answer with no readable cache does not succeed empty")
    func unchangedWithNoReadableCacheDoesNotSucceed() async throws {
        let harness = try SyncHarness(recording: true)
        let recorder = try #require(harness.recorder)
        harness.source.script(.notModified, for: .formulae)
        harness.source.script(.notModified, for: .casks)

        let result = await harness.engine.sync()

        #expect(result.error == .malformedPayload)
        #expect(await harness.engine.status == .failed(.malformedPayload))
        #expect(recorder.publishedPaths.isEmpty, "an empty catalog was published")
    }

    @Test("A degenerate first sync stays non-fatal and leaves no snapshot behind")
    func degenerateFirstSyncIsNonFatal() async throws {
        let harness = try SyncHarness()
        harness.source.script(.notModified, for: .formulae)
        harness.source.script(.notModified, for: .casks)

        let result = await harness.engine.sync()

        #expect(result.error == .malformedPayload)
        #expect(await harness.engine.cachedSnapshot() == nil)
        #expect(FileManager.default.fileExists(atPath: harness.store.snapshotURL.path) == false)
    }

    @Test("Recovery from a poisoned snapshot is unconditional")
    func poisonedSnapshotForcesAnUnconditionalFetch() async throws {
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
        // Genuine validators for both sources are on disk...
        let state = try #require(try harness.store.loadState())
        #expect(state.sources[.formulae]?.validators.etag == "V1")
        #expect(state.sources[.casks]?.validators.etag == "C1")

        // ...certifying a snapshot that is now degenerate.
        try harness.poisonSnapshot()
        harness.source.script(.payload(Payload.formulae(["wget", "curl"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        let result = await harness.engine.sync()

        // No conditional request: replaying the validators would be answered 304
        // and leave the machine on the poisoned catalog forever. This falls out
        // of the read guard through the existing CS6 `revalidatable` path — no
        // branch was added for it.
        #expect(harness.source.requests(for: .formulae).last?.validators == nil)
        #expect(harness.source.requests(for: .casks).last?.validators == nil)
        #expect(result.value?.packages.map(\.name).sorted() == ["curl", "iterm2", "wget"])
        #expect(try harness.store.loadSnapshot()?.packages.count == 3)
    }
}
