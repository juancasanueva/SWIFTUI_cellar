import Foundation
import Testing

@testable import Catalog

/// The dashboard's rows, and the one thing rendering them may never do
/// (`system-health`, "Health is a projection over resident state and acquires
/// nothing to render" and "Every row states what it does not know"; design HD9).
///
/// Rendering acquires nothing. Not a subprocess, not a sync, not a scan, not a
/// measurement, not an inventory refresh, and above all not a timer — a health
/// dashboard that re-measures because you looked at it is a background job with
/// a window attached.
///
/// The projection is a pure function of its inputs, so the whole of that claim is
/// provable here with no store, no clock and no process: there is nothing in the
/// signature to trigger.
@Suite("Health projection")
struct HealthProjectionTests {

    private static let now = Date(timeIntervalSince1970: 1_786_081_527)

    private static func inputs(
        _ overrides: [HealthInput: HealthSignal] = [:],
        measurements: [HealthInput: HealthMeasurement] = [:]
    ) -> HealthInputs {
        var signals = Dictionary(
            uniqueKeysWithValues: HealthInput.allCases.map { ($0, HealthSignal.answered(1.0)) }
        )
        for (input, signal) in overrides { signals[input] = signal }
        return HealthInputs(signals, measurements: measurements)
    }

    private static func row(_ content: HealthContent, _ input: HealthInput) throws -> HealthRow {
        try #require(content.rows.first { $0.input == input }, "no row for \(input)")
    }

    // MARK: - 7.1 — building acquires nothing

    /// The signature is the proof: there is no seam in it to trigger, and the
    /// implementation names none.
    @Test("Building the projection can reach no process, sync, scan, refresh or timer")
    func buildingReachesNothing() throws {
        let source = try Self.declarations(of: "HealthProjection.swift")

        // Call-shaped tokens, not bare words. The projection legitimately *reads*
        // a `HealthMeasurement` — it just never takes one — so a substring scan
        // for "measure" would flag `unmeasured` and the vocabulary itself.
        for forbidden in [
            "ProcessLaunching", "Process(", "URLSession", "FileManager",
            "CatalogStore", "CatalogSyncEngine",
            "refresh(", "scan(", "measure(", "sync(", "load(", "fetch(",
            "Timer", "Task {", "Task.detached", "DispatchQueue", "AsyncStream", "sleep"
        ] {
            #expect(source.contains(forbidden) == false, "the projection reaches \(forbidden)")
        }

        // Positive anchor, so a scan that read nothing cannot pass silently.
        #expect(source.contains("HealthProjection"), "the source scan read nothing")
        #expect(source.contains("static func build(inputs: HealthInputs, now: Date) async -> HealthContent"))
        // `@concurrent` on its own line before the modifier (M1 convention), so
        // the build runs off the main actor rather than on it.
        #expect(source.contains("@concurrent\n    public static func build"))
    }

    @Test("The projection is a function of its inputs")
    func theProjectionIsAFunctionOfItsInputs() async {
        let inputs = Self.inputs([.outdated: .answered(0.3), .cache: .unknown(.unmeasured)])

        let first = await HealthProjection.build(inputs: inputs, now: Self.now)
        let second = await HealthProjection.build(inputs: inputs, now: Self.now)

        #expect(first == second)
        #expect(first.rows == second.rows)
        #expect(first.score == second.score)
        // Non-trivial: a real, mixed projection rather than an empty one.
        #expect(first.rows.count == HealthInput.allCases.count)
    }

    /// An unmeasured signal stays unmeasured. It is not substituted with a
    /// computed default, and asking for it does not obtain it.
    @Test("An unmeasured signal is projected as unmeasured, with no default substituted")
    func anUnmeasuredSignalStaysUnmeasured() async throws {
        let content = await HealthProjection.build(
            inputs: Self.inputs([.cache: .unknown(.unmeasured)]),
            now: Self.now
        )

        let cache = try Self.row(content, .cache)
        #expect(cache.isAnswered == false)
        #expect(cache.summary == nil, "an unmeasured row rendered a value anyway")
        #expect(cache.unknownReason == .unmeasured)
    }

    /// Doctor is user-initiated, so a freshly opened section shows it as not run
    /// rather than running it.
    @Test("With no doctor evidence the doctor row reports not-run and offers a re-measure")
    func doctorRunsOnlyWhenAsked() async throws {
        let content = await HealthProjection.build(
            inputs: Self.inputs([.doctor: .unknown(.notRun)]),
            now: Self.now
        )

        let doctor = try Self.row(content, .doctor)
        #expect(doctor.isAnswered == false)
        #expect(doctor.unknownReason == .notRun)
        #expect(doctor.summary == nil)
        // The control offered is the measurement, and it is offered from this row.
        #expect(doctor.remediation == .runDoctor)
    }

    @Test("The projection carries the moment it was built rather than reading a clock")
    func theProjectionCarriesTheMomentItWasHanded() async {
        let content = await HealthProjection.build(inputs: Self.inputs(), now: Self.now)
        let later = await HealthProjection.build(
            inputs: Self.inputs(),
            now: Self.now.addingTimeInterval(600)
        )

        #expect(content.generatedAt == Self.now)
        #expect(later.generatedAt == Self.now.addingTimeInterval(600))
        // Everything else is identical, so `now` is a stamp rather than an input
        // to any of the rules.
        #expect(content.rows == later.rows)
        #expect(content.score == later.score)
    }

    // MARK: - 7.2 — one row per input, each naming what it does not know

    /// One row per input. `advisoryCoverage` carries 15 points of the score, so
    /// it gets a row of its own directly under the vulnerabilities it qualifies:
    /// a weighted signal with no row is a number the user cannot explain.
    @Test("The projection has exactly one row per input, in a fixed order")
    func thereIsOneRowPerInput() async {
        let content = await HealthProjection.build(inputs: Self.inputs(), now: Self.now)

        #expect(content.rows.map(\.input) == [
            .outdated, .vulnerable, .advisoryCoverage, .orphans, .duplicateVersions, .cache, .lastUpdate, .doctor
        ])
        #expect(content.rows.count == HealthInput.allCases.count)
        // Every row is titled, and no two share a title.
        #expect(content.rows.allSatisfy { $0.title.isEmpty == false })
        #expect(Set(content.rows.map(\.title)).count == content.rows.count)
    }

    /// The M4 substitution, forbidden per reason rather than per row: an
    /// inventory nobody could answer for is never "0 vulnerable".
    @Test(
        "An uncovered, unavailable or partial scan is never rendered as zero vulnerabilities",
        arguments: [HealthUnknownReason.notCovered, .unavailable, .partial, .cancelled, .failed]
    )
    func anUncoveredInventoryIsNotZeroVulnerabilities(reason: HealthUnknownReason) async throws {
        let content = await HealthProjection.build(
            inputs: Self.inputs([.vulnerable: .unknown(reason)]),
            now: Self.now
        )

        let vulnerable = try Self.row(content, .vulnerable)
        #expect(vulnerable.isAnswered == false)
        #expect(vulnerable.summary == nil, "an unanswered scan rendered a count")
        #expect(vulnerable.unknownReason == reason, "the row does not name why it cannot answer")
        // And it offers no remediation, because there is nothing to remediate.
        #expect(vulnerable.remediation == .none)
    }

    @Test("Unknown orphans are never rendered as zero orphans")
    func unknownOrphansAreNotZeroOrphans() async throws {
        let content = await HealthProjection.build(
            inputs: Self.inputs([.orphans: .unknown(.unknown)]),
            now: Self.now
        )

        let orphans = try Self.row(content, .orphans)
        #expect(orphans.summary == nil)
        #expect(orphans.unknownReason == .unknown)
        #expect(orphans.isAnswered == false)
    }

    @Test(
        "An incomplete or failed disk measurement is never a complete size",
        arguments: [HealthInput.duplicateVersions, .cache]
    )
    func anIncompleteDiskMeasurementNamesItsGap(input: HealthInput) async throws {
        let content = await HealthProjection.build(
            inputs: Self.inputs([input: .unknown(.failed)]),
            now: Self.now
        )

        let row = try Self.row(content, input)
        #expect(row.summary == nil, "an incomplete measurement was presented as a total")
        #expect(row.unknownReason == .failed)
    }

    @Test(
        "An absent, unreadable or future-dated reading is never an age",
        arguments: [HealthUnknownReason.absent, .unreadable, .futureDated]
    )
    func anAbsentLastUpdateReadingIsNotAnAge(reason: HealthUnknownReason) async throws {
        let content = await HealthProjection.build(
            inputs: Self.inputs([.lastUpdate: .unknown(reason)]),
            now: Self.now
        )

        let staleness = try Self.row(content, .lastUpdate)
        #expect(staleness.summary == nil, "a non-answer was rendered as an age")
        #expect(staleness.unknownReason == reason)
        #expect(staleness.isAnswered == false)
        // No freshness verdict either: the row offers nothing to act on.
        #expect(staleness.remediation == .none)
    }

    /// The control that keeps every assertion above meaningful: an answered
    /// signal **does** render its measurement.
    @Test("An answered row renders the measurement it was given")
    func anAnsweredRowRendersItsMeasurement() async throws {
        let content = await HealthProjection.build(
            inputs: Self.inputs(
                [.vulnerable: .answered(0.4)],
                measurements: [.vulnerable: HealthMeasurement(summary: "3 vulnerable")]
            ),
            now: Self.now
        )

        let vulnerable = try Self.row(content, .vulnerable)
        #expect(vulnerable.isAnswered)
        #expect(vulnerable.summary == "3 vulnerable")
        #expect(vulnerable.unknownReason == nil)
    }

    /// Both halves, rather than only the answered one. A scan that covered part
    /// of the inventory must not present its result as covering all of it.
    @Test("A partially answered scan reports what it answered and what it did not")
    func aPartiallyAnsweredScanReportsBothHalves() async throws {
        let content = await HealthProjection.build(
            inputs: Self.inputs(
                [.vulnerable: .answered(0.8), .advisoryCoverage: .answered(0.5)],
                measurements: [
                    .vulnerable: HealthMeasurement(
                        summary: "1 vulnerable in 40 answered",
                        unanswered: .partial
                    )
                ]
            ),
            now: Self.now
        )

        let vulnerable = try Self.row(content, .vulnerable)
        #expect(vulnerable.isPartiallyAnswered, "a partial scan reported only one half")
        #expect(vulnerable.summary == "1 vulnerable in 40 answered")
        #expect(vulnerable.unknownReason == .partial)
        // Both halves at once: answered *and* carrying a named gap.
        #expect(vulnerable.isAnswered)
    }

    // MARK: - 7.3 — the remediation vocabulary is closed

    @Test("The remediation vocabulary is exactly the five shipped entries")
    func theRemediationVocabularyIsClosed() {
        #expect(HealthRemediation.allCases == [.upgradeAll, .autoremove, .cleanupCache, .runDoctor, .none])
        #expect(HealthRemediation.allCases.count == 5)

        // No new mutating verb, no Homebrew update, no doctor repair.
        let names = HealthRemediation.allCases.map(\.rawValue).joined(separator: " ").lowercased()
        for forbidden in ["update", "fix", "repair", "resolve", "install", "uninstall", "pin", "zap", "reinstall"] {
            #expect(names.contains(forbidden) == false, "a \(forbidden) remediation exists")
        }
    }

    @Test("Each offered verb comes from the row that motivated it")
    func eachVerbComesFromItsOwnRow() async {
        let content = await HealthProjection.build(
            inputs: Self.inputs([
                .outdated: .answered(0.2),
                .orphans: .answered(0.2),
                .cache: .answered(0.2),
                .duplicateVersions: .answered(0.2),
                .doctor: .answered(0.2)
            ]),
            now: Self.now
        )

        let offered = Dictionary(
            uniqueKeysWithValues: content.rows.map { ($0.input, $0.remediation) }
        )
        #expect(offered[.outdated] == .upgradeAll)
        #expect(offered[.orphans] == .autoremove)
        #expect(offered[.cache] == .cleanupCache)
        #expect(offered[.doctor] == .runDoctor)
        // No repair is offered for a doctor warning: the doctor row's verb
        // re-measures, and there is no second doctor verb.
        #expect(content.rows.count { $0.remediation == .runDoctor } == 1)
    }

    /// A row with nothing to offer offers `none` — a case, not an inert control.
    @Test("The vulnerability and staleness rows offer no remediation at all")
    func rowsWithoutARemediationOfferNone() async throws {
        let content = await HealthProjection.build(
            inputs: Self.inputs([.vulnerable: .answered(0.1), .lastUpdate: .answered(0.1)]),
            now: Self.now
        )

        #expect(try Self.row(content, .vulnerable).remediation == .none)
        #expect(try Self.row(content, .lastUpdate).remediation == .none)
        // And `duplicateVersions` reclaims disk through the shipped cleanup verb
        // rather than through a new one.
        #expect(try Self.row(content, .duplicateVersions).remediation == .cleanupCache)
    }

    // MARK: - 7.4 — the score and its caveat come from one value

    @Test("The score and its unknown set are read off a single value")
    func theScoreAndItsCaveatComeFromOneValue() async throws {
        let content = await HealthProjection.build(
            inputs: Self.inputs([.doctor: .unknown(.notRun)]),
            now: Self.now
        )

        guard case .scored(let score) = content.score else {
            Issue.record("the projection produced no score")
            return
        }
        #expect(score.value == 100)
        #expect(score.isComplete == false)
        #expect(score.unknownInputs.map(\.input) == [.doctor])

        // There is no second view onto the number anywhere on the content, so a
        // surface cannot render one without the other.
        let source = try Self.declarations(of: "HealthProjection.swift")
        #expect(source.contains("let score: HealthScoreState"))
        let bareValues = source
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.contains("var scoreValue") || $0.contains("-> Int") }
        #expect(bareValues.isEmpty, "the content exposes the number apart from its unknowns")
    }

    @Test("With nothing answered the projection still renders its rows and reports no number")
    func nothingAnsweredStillRendersRows() async {
        let content = await HealthProjection.build(
            inputs: HealthInputs(Dictionary(
                uniqueKeysWithValues: HealthInput.allCases.map {
                    ($0, HealthSignal.unknown(.unmeasured))
                }
            )),
            now: Self.now
        )

        guard case .unscorable(let unknownInputs) = content.score else {
            Issue.record("an all-unknown input set produced a number")
            return
        }
        #expect(unknownInputs.count == 8)
        // The rows are still there, each naming its own reason — the surface has
        // something honest to show rather than a blank panel.
        #expect(content.rows.count == HealthInput.allCases.count)
        #expect(content.rows.allSatisfy { $0.summary == nil })
        #expect(content.rows.allSatisfy { $0.unknownReason == .unmeasured })
    }

    private static func declarations(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Catalog/\(file)"),
            encoding: .utf8
        )
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
    }
}
