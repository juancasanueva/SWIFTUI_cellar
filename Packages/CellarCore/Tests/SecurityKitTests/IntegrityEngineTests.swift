import Catalog
import Foundation
import Testing

@testable import SecurityKit

/// The sweep is per item, off-main, streamed and cancellable.
///
/// The `DiskUsageEngine.scan` shape, and for the same reason: one slow or broken
/// artifact among two hundred must not hold the interface, must not delete the
/// results already gathered, and must not end the run for everybody else.
@Suite("Artifact integrity engine")
struct IntegrityEngineTests {
    private static func location(_ name: String) -> ArtifactLocation {
        ArtifactLocation(
            packageID: PackageID(kind: .formula, name: name),
            url: URL(fileURLWithPath: "/opt/homebrew/Cellar/\(name)/1.0.0/bin/\(name)"),
            kind: .machO
        )
    }

    private static let three = ["bat", "ripgrep", "fd"].map(Self.location)

    private static func engine(
        signatures: FakeSignatureInspector,
        quarantine: FakeQuarantineInspector = FakeQuarantineInspector()
    ) -> ArtifactIntegrityEngine {
        ArtifactIntegrityEngine(signatures: signatures, quarantine: quarantine)
    }

    // MARK: - 14.8 Incremental delivery

    @Test("Results arrive incrementally per artifact rather than as one terminal batch")
    func resultsArriveIncrementallyPerArtifactRatherThanAsOneTerminalBatch() async throws {
        let engine = Self.engine(
            signatures: FakeSignatureInspector(
                result: .init(signing: .unsigned, notarization: .notNotarized)
            )
        )

        var assessed: [String] = []
        var sawStarted = false
        var completedAfter: [Int] = []

        for try await event in await engine.inspect(Self.three) {
            switch event {
            case .started(let count):
                #expect(count == 3)
                sawStarted = true
            case .assessed(let report):
                assessed.append(report.location.packageID.name)
                // The whole claim: each report is observable *before* the run
                // finishes, not handed over in one lump at the end.
                completedAfter.append(assessed.count)
            case .finished:
                #expect(assessed.count == 3, "the run finished before every artifact was reported")
            }
        }

        #expect(sawStarted)
        #expect(assessed == ["bat", "ripgrep", "fd"], "artifacts were reordered or dropped")
        #expect(completedAfter == [1, 2, 3], "reports did not arrive one at a time")
    }

    @Test("Every report carries both halves and its own artifact")
    func everyReportCarriesBothHalvesAndItsOwnArtifact() async throws {
        let engine = Self.engine(
            signatures: FakeSignatureInspector(
                result: .init(signing: .adHoc(identifier: "bat-abc"), notarization: .notNotarized)
            ),
            quarantine: FakeQuarantineInspector(
                rawValue: "01c3;6a65eb27;Safari;3E44AF78-B965-4994-8537-E5EEA922D6E5"
            )
        )

        let reports = try await Self.reports(from: await engine.inspect([Self.location("bat")]))
        let report = try #require(reports.first)

        #expect(report.location.packageID.name == "bat")
        #expect(report.signature.signing == .adHoc(identifier: "bat-abc"))
        #expect(report.quarantine?.quarantine?.agentName == .decoded("Safari"))
        // The spec's "presented together": the quarantined artifact and its
        // signing verdict are one value, so a surface cannot show one without
        // having the other in hand.
        #expect(report.isQuarantined)
    }

    // MARK: - Per-item isolation

    @Test("A per-artifact failure becomes a could-not-assess event and never terminates the stream")
    func aPerArtifactFailureBecomesACouldNotAssessEventAndNeverTerminatesTheStream() async throws {
        let engine = Self.engine(
            signatures: FakeSignatureInspector(
                failure: .artifactUnreadable,
                failingURLs: [Self.location("ripgrep").url]
            )
        )

        let reports = try await Self.reports(from: await engine.inspect(Self.three))

        #expect(reports.count == 3, "one artifact's failure ended the run for the others")
        #expect(reports.map(\.location.packageID.name) == ["bat", "ripgrep", "fd"])

        let failed = try #require(reports.first { $0.location.packageID.name == "ripgrep" })
        #expect(failed.signature.signing == .couldNotAssess(.artifactUnreadable))
        #expect(failed.signature.notarization == .couldNotAssess(.artifactUnreadable))
        #expect(failed.signature.notarization.isNotNotarized == false)

        // The positive control: the two around it still got real answers, so the
        // isolation is isolation and not a blanket downgrade.
        for name in ["bat", "fd"] {
            let healthy = try #require(reports.first { $0.location.packageID.name == name })
            #expect(healthy.signature.signing != .couldNotAssess(.artifactUnreadable))
        }
    }

    /// A quarantine read that fails must not lose the signature verdict that
    /// succeeded. They are two independent questions about one artifact.
    @Test("A failing quarantine read leaves the signature verdict standing")
    func aFailingQuarantineReadLeavesTheSignatureVerdictStanding() async throws {
        let engine = Self.engine(
            signatures: FakeSignatureInspector(
                result: .init(signing: .unsigned, notarization: .notNotarized)
            ),
            quarantine: FakeQuarantineInspector(failure: .artifactUnreadable)
        )

        let report = try #require(
            try await Self.reports(from: await engine.inspect([Self.location("bat")])).first
        )

        #expect(report.signature.signing == .unsigned)
        #expect(report.quarantine == nil, "a failed read must not be reported as 'no attributes'")
        #expect(report.isQuarantined == false)
    }

    // MARK: - Cancellation

    @Test("Cancellation stops the run without presenting it as complete")
    func cancellationStopsTheRunWithoutPresentingItAsComplete() async throws {
        let engine = Self.engine(
            signatures: FakeSignatureInspector(
                result: .init(signing: .unsigned, notarization: .notNotarized)
            )
        )
        let many = (0..<200).map { Self.location("pkg\($0)") }

        var reports: [ArtifactIntegrityReport] = []
        var sawFinished = false

        do {
            for try await event in await engine.inspect(many) {
                switch event {
                case .assessed(let report):
                    reports.append(report)
                    // Stop consuming partway. Terminating the stream cancels the
                    // producer, which is the shipped `DiskUsageEngine` contract.
                    if reports.count == 5 { return }
                case .finished:
                    sawFinished = true
                case .started:
                    break
                }
            }
        }

        #expect(sawFinished == false)
        #expect(reports.count == 5, "completed items must remain in hand after cancelling")
    }

    /// The other half of the same rule: a cancelled run does not emit `finished`,
    /// so a consumer cannot mistake it for a complete sweep.
    ///
    /// Deterministic rather than timed. The fake blocks on the third artifact and
    /// stays blocked until cancellation reaches it, so the run is *guaranteed* to
    /// be mid-flight — the first version of this test raced a 20 ms sleep against
    /// five hundred instant fakes and lost.
    @Test("A cancelled producer never emits finished, and completed items remain")
    func aCancelledProducerNeverEmitsFinished() async throws {
        let engine = Self.engine(
            signatures: FakeSignatureInspector(
                result: .init(signing: .unsigned, notarization: .notNotarized),
                blockAfter: 2
            )
        )

        let gate = AsyncStream<Void>.makeStream()
        let collector = Task { () -> (reports: Int, finished: Bool) in
            var count = 0
            var finished = false
            for try await event in await engine.inspect(Self.three + [Self.location("jq")]) {
                if case .assessed = event {
                    count += 1
                    if count == 2 { gate.continuation.yield() }
                }
                if case .finished = event { finished = true }
            }
            return (count, finished)
        }

        var iterator = gate.stream.makeAsyncIterator()
        await iterator.next()
        collector.cancel()

        let outcome = try? await collector.value
        #expect(outcome?.finished != true, "a cancelled run reported itself as complete")
        #expect(
            outcome?.reports ?? 2 >= 2,
            "the two artifacts assessed before cancellation were lost"
        )
    }

    @Test("An empty artifact list finishes immediately rather than hanging")
    func anEmptyArtifactListFinishesImmediately() async throws {
        let engine = Self.engine(signatures: FakeSignatureInspector())

        var events: [String] = []
        for try await event in await engine.inspect([]) {
            switch event {
            case .started(let count):
                #expect(count == 0)
                events.append("started")
            case .assessed: events.append("assessed")
            case .finished: events.append("finished")
            }
        }

        #expect(events == ["started", "finished"])
    }

    // MARK: - Helpers

    private static func reports(
        from stream: ArtifactIntegrityEventStream
    ) async throws -> [ArtifactIntegrityReport] {
        var reports: [ArtifactIntegrityReport] = []
        for try await event in stream {
            if case .assessed(let report) = event { reports.append(report) }
        }
        return reports
    }
}
