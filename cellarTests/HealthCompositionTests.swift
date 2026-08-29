//
//  HealthCompositionTests.swift
//  cellarTests
//

import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import Foundation
import SecurityKit
import Testing

@testable import cellar

/// The app half of the health dashboard (`system-health` SH7, SH8, SH11; design
/// HD6, HD9).
///
/// `Catalog` computes the score over a re-declared scalar vocabulary and knows
/// nothing about a byte, a keg or a CVE. Every translation from a shipped
/// capability's value into a `HealthSignal` therefore happens **here**, in the
/// only target that can see all of them — which makes this file the whole surface
/// on which "an unanswered signal becomes a clean one" could go wrong.
///
/// The launcher is a **per-instance** `CompositionLauncher`, and no call site is
/// added to `SecurityCompositionSupport`'s `CompositionRequestSpy`: its
/// `nonisolated(unsafe) static var count` plus `install()` reset is the shape that
/// produces a false zero when suites run concurrently, and Health composes
/// SecurityKit, so this is exactly the suite that would hit it.
@Suite("Health composition", .timeLimit(.minutes(1)))
struct HealthCompositionTests {

    // MARK: - 10.1 — no unanswered state may become `.answered(1.0)`

    /// Every upstream shape that reads like good news when it is mapped
    /// carelessly.
    ///
    /// The assertion is deliberately two-sided: the reading must be
    /// `.unknown(reason)` **and** must not be `.answered(1.0)`. The second half
    /// looks redundant next to the first and is not — it is the assertion that
    /// still fails if `HealthSignal` ever grows a third case that a careless
    /// mapping could reach.
    /// Coverage is measured against the packages the curated table can map at
    /// all. The table is a few percent of any inventory by design, so measuring
    /// against the whole inventory would be a fixed penalty on every Mac rather
    /// than a fact about this one. The gap is not hidden: it is the summary.
    @Test("Advisory coverage is measured against mappable packages, and names the unmappable rest")
    func advisoryCoverageIsMeasuredAgainstMappablePackages() {
        let state = SecurityScanState.content(Self.result(partial: false))

        let fullyAnswered = HealthComposition.advisoryCoverage(
            state: state,
            totals: HealthFixtures.totals(vulnerable: 0, clean: 7, notCovered: 177, unavailable: 0)
        )
        #expect(fullyAnswered.signal == .answered(1.0))
        #expect(fullyAnswered.measurement?.summary == "7 of 7 checkable packages answered · 177 cannot be checked yet")
        #expect(fullyAnswered.measurement?.unanswered == .notCovered)

        let halfUnavailable = HealthComposition.advisoryCoverage(
            state: state,
            totals: HealthFixtures.totals(vulnerable: 1, clean: 4, notCovered: 100, unavailable: 5)
        )
        #expect(halfUnavailable.signal == .answered(0.0))
        #expect(halfUnavailable.measurement?.summary == "5 of 10 checkable packages answered · 100 cannot be checked yet")

        let everythingMappable = HealthComposition.advisoryCoverage(
            state: state,
            totals: HealthFixtures.totals(vulnerable: 0, clean: 10, notCovered: 0, unavailable: 0)
        )
        #expect(everythingMappable.measurement?.summary == "10 of 10 checkable packages answered")
        #expect(everythingMappable.measurement?.unanswered == nil)

        let nothingMappable = HealthComposition.advisoryCoverage(
            state: state,
            totals: HealthFixtures.totals(vulnerable: 0, clean: 0, notCovered: 12, unavailable: 0)
        )
        #expect(nothingMappable.signal == .unknown(.notCovered))
        #expect(nothingMappable.measurement == nil)
    }

    @Test("Security coverage that answered nothing is unknown, never zero vulnerable")
    func securityCoverageThatAnsweredNothingIsUnknown() {
        let uncovered = HealthFixtures.totals(vulnerable: 0, clean: 0, notCovered: 12, unavailable: 0)
        let unavailable = HealthFixtures.totals(vulnerable: 0, clean: 0, notCovered: 0, unavailable: 12)

        for totals in [uncovered, unavailable] {
            let reading = HealthComposition.vulnerable(state: .content(Self.result(partial: false)), totals: totals)
            #expect(reading.signal.unknownReason != nil, "an inventory nobody answered for scored a number")
            #expect(reading.signal != .answered(1.0))
            #expect(reading.measurement == nil, "an unanswered row carried a summary to render")
        }

        #expect(
            HealthComposition.vulnerable(
                state: .content(Self.result(partial: false)),
                totals: uncovered
            ).signal.unknownReason == .notCovered
        )
    }

    @Test("Every non-answering scan state is unknown with its own reason")
    func everyNonAnsweringScanStateIsUnknown() {
        let totals = HealthFixtures.totals(vulnerable: 0, clean: 10, notCovered: 0, unavailable: 0)
        let states: [(SecurityScanState, HealthUnknownReason)] = [
            (.idle, .unmeasured),
            (.loading(stale: nil), .unmeasured),
            (.failed(.offline, stale: nil), .failed),
            (.cancelled(stale: nil), .cancelled)
        ]

        for (state, expected) in states {
            for reading in [
                HealthComposition.vulnerable(state: state, totals: totals),
                HealthComposition.advisoryCoverage(state: state, totals: totals)
            ] {
                #expect(reading.signal.unknownReason == expected, "\(state) mapped to \(reading.signal)")
                #expect(reading.signal != .answered(1.0))
            }
        }
    }

    /// A partially answered scan reports **both halves** (SH8).
    ///
    /// The answered part is a real number and the gap is named beside it. This is
    /// the one row where "answered" and "unknown" are both true at once, and the
    /// shape has to allow it or the requirement is unexpressible.
    @Test("A partial scan answers and names its gap")
    func aPartialScanAnswersAndNamesItsGap() throws {
        let totals = HealthFixtures.totals(vulnerable: 1, clean: 9, notCovered: 5, unavailable: 0)
        let reading = HealthComposition.vulnerable(state: .partial(Self.result(partial: true)), totals: totals)

        let health = try #require(reading.signal.health)
        #expect(health < 1.0, "one vulnerable package in ten answered scored as perfect")
        let measurement = try #require(reading.measurement)
        #expect(measurement.unanswered == .partial)
        #expect(measurement.summary.contains("1"))
        #expect(measurement.summary.contains("5"), "the unanswered remainder is not in the summary")
    }

    @Test("Unknown orphans are unknown, never zero orphans")
    func unknownOrphansAreUnknown() throws {
        #expect(HealthComposition.orphans(.unknown).signal.unknownReason == .unknown)
        #expect(HealthComposition.orphans(.unknown).signal != .answered(1.0))
        #expect(HealthComposition.orphans(nil).signal.unknownReason == .unmeasured)
        #expect(HealthComposition.orphans(.notApplicable).signal.unknownReason == .unmeasured)

        // …and a real answer of zero is a different fact, which is the whole
        // point of the distinction.
        let none = HealthComposition.orphans(.known(names: [], reportedCount: 0, currentlyOnDiskBytes: 0))
        #expect(none.signal == .answered(1.0))
        #expect(try #require(none.measurement).summary.contains("0"))
    }

    @Test("A failed or absent disk measurement is never a complete size")
    func aFailedOrAbsentDiskMeasurementIsNeverAcompleteSize() throws {
        #expect(HealthComposition.cache(snapshot: nil, reclaimable: nil).signal.unknownReason == .unmeasured)
        #expect(HealthComposition.duplicateVersions(nil).signal.unknownReason == .unmeasured)

        let failedCache = HealthFixtures.snapshot(
            rootStates: [.cellar: .present, .caskroom: .present, .cache: .failed("permission denied")]
        )
        let cacheReading = HealthComposition.cache(snapshot: failedCache, reclaimable: nil)
        #expect(cacheReading.signal.unknownReason == .failed)
        #expect(cacheReading.signal != .answered(1.0))

        let failedCellar = HealthFixtures.snapshot(
            rootStates: [.cellar: .failed("permission denied"), .caskroom: .present, .cache: .present]
        )
        #expect(HealthComposition.duplicateVersions(failedCellar).signal.unknownReason == .failed)

        // An incomplete snapshot whose own root is fine still answers — and names
        // the gap, rather than presenting the total as complete.
        let incomplete = HealthFixtures.snapshot(
            cacheBytes: 1 << 30,
            warnings: [DiskUsageWarning(area: .caskroom, path: "/opt/homebrew/Caskroom/x", message: "skipped")]
        )
        let partial = HealthComposition.cache(snapshot: incomplete, reclaimable: nil)
        #expect(partial.signal.health != nil)
        #expect(try #require(partial.measurement).unanswered == .partial)
    }

    @Test("An unknown reclaimable total is unknown when there is no snapshot behind it")
    func anUnknownReclaimableTotalIsUnknown() throws {
        #expect(HealthComposition.cache(snapshot: nil, reclaimable: .unknown).signal.unknownReason == .unknown)

        let fallback = HealthComposition.cache(snapshot: nil, reclaimable: .reportedFooter(bytes: 1 << 30))
        #expect(fallback.signal == .answered(1.0))
        #expect(try #require(fallback.measurement).summary.isEmpty == false)
    }

    @Test("Every non-answering last-update reading is unknown, never fresh")
    func everyNonAnsweringLastUpdateReadingIsUnknown() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let cases: [(HomebrewLastUpdate?, HealthUnknownReason)] = [
            (nil, .unmeasured),
            (.absent, .absent),
            (.unreadable, .unreadable),
            (.futureDated(now.addingTimeInterval(3_600)), .futureDated)
        ]
        for (reading, expected) in cases {
            let mapped = HealthComposition.lastUpdate(reading, now: now)
            #expect(mapped.signal.unknownReason == expected, "\(String(describing: reading)) mapped to \(mapped.signal)")
            #expect(mapped.signal != .answered(1.0), "a non-answer read as a freshly updated Homebrew")
            #expect(mapped.measurement == nil)
        }

        let fresh = HealthComposition.lastUpdate(.read(now.addingTimeInterval(-3_600)), now: now)
        #expect(fresh.signal == .answered(1.0))
        #expect(try #require(fresh.measurement).summary.isEmpty == false)
    }

    @Test("A doctor that never ran is not a doctor that found nothing")
    func aDoctorThatNeverRanIsNotADoctorThatFoundNothing() throws {
        #expect(HealthComposition.doctor(nil).signal.unknownReason == .notRun)
        #expect(HealthComposition.doctor(nil).signal != .answered(1.0))
        #expect(
            HealthComposition.doctor(.unavailable(.cancelled)).signal.unknownReason == .cancelled
        )
        #expect(
            HealthComposition.doctor(.unavailable(.brewUnavailable)).signal.unknownReason == .unavailable
        )
        #expect(
            HealthComposition.doctor(.unavailable(.signalled(9))).signal.unknownReason == .failed
        )

        let clean = HealthComposition.doctor(.clean(HealthFixtures.evidence(warnings: 0, ready: true)))
        #expect(clean.signal == .answered(1.0))
        let noisy = HealthComposition.doctor(.issues(HealthFixtures.evidence(warnings: 5)))
        #expect(try #require(noisy.signal.health) < 1.0)
        #expect(try #require(noisy.measurement).summary.contains("5"))

        let unrecognised = HealthComposition.doctor(.issues(HealthFixtures.evidence(warnings: 0, partial: true)))
        #expect(try #require(unrecognised.measurement).unanswered == .partial)
    }

    @Test("An unavailable or unloaded inventory is unknown, never zero outdated")
    func anUnavailableInventoryIsUnknown() throws {
        let absent = HealthComposition.outdated(browse: HealthFixtures.browse([], isAvailable: false), metadata: nil)
        #expect(absent.signal.unknownReason == .unavailable)
        #expect(absent.signal != .answered(1.0))

        let empty = HealthComposition.outdated(browse: HealthFixtures.browse([]), metadata: nil)
        #expect(empty.signal.unknownReason == .unmeasured, "an inventory that has not loaded scored as perfect")

        let loaded = HealthFixtures.browse([
            HealthFixtures.package("git", outdated: true, extraVersions: []),
            HealthFixtures.package("wget"),
            HealthFixtures.package("jq"),
            HealthFixtures.package("fd")
        ])
        let reading = HealthComposition.outdated(browse: loaded, metadata: nil)
        #expect(try #require(reading.signal.health) < 1.0)
        #expect(try #require(reading.measurement).summary.contains("1"))
    }

    /// The whole mapping surface, swept in one pass.
    ///
    /// Individually each mapping above is asserted; this is the claim that no
    /// **ninth** input was added with no mapping and no test, which is how the
    /// eighth would have gone unnoticed.
    @Test("Nothing unanswered anywhere composes into a perfect score")
    func nothingUnansweredAnywhereComposesIntoAperfectScore() {
        let inputs = HealthComposition.inputs(
            browse: HealthFixtures.browse([], isAvailable: false),
            metadata: nil,
            scan: .idle,
            coverage: HealthFixtures.totals(vulnerable: 0, clean: 0, notCovered: 0, unavailable: 0),
            orphans: .unknown,
            reclaimable: .unknown,
            snapshot: nil,
            lastUpdate: nil,
            doctor: nil,
            now: Date(timeIntervalSince1970: 2_000_000)
        )

        for input in HealthInput.allCases {
            #expect(inputs[input].health == nil, "\(input) answered from an entirely unmeasured machine")
        }
        #expect(HealthScoring.score(inputs) == .unscorable(
            unknownInputs: HealthInput.allCases.map {
                HealthUnknown(input: $0, reason: inputs[$0].unknownReason ?? .unmeasured)
            }
        ))
    }

    // MARK: - 10.2 — rendering acquires nothing

    @MainActor
    @Test("Composing and projecting Health spawns no process")
    func composingAndProjectingHealthSpawnsNoProcess() async {
        let launcher = CompositionLauncher()
        let source = BrewDoctorSource(launcher: launcher)
        let store = HealthStore(doctorSource: source, metadataAccess: StubFileMetadataAccess(answers: [:]))

        let inputs = HealthComposition.inputs(
            browse: HealthFixtures.browse([HealthFixtures.package("git", outdated: true)]),
            metadata: nil,
            scan: .content(Self.result(partial: false)),
            coverage: HealthFixtures.totals(vulnerable: 0, clean: 4, notCovered: 0, unavailable: 0),
            orphans: .known(names: [], reportedCount: 0, currentlyOnDiskBytes: 0),
            reclaimable: .reportedFooter(bytes: 0),
            snapshot: HealthFixtures.snapshot(),
            lastUpdate: store.lastUpdate,
            doctor: store.doctor,
            now: Date(timeIntervalSince1970: 2_000_000)
        )
        let content = await HealthProjection.build(inputs: inputs, now: Date(timeIntervalSince1970: 2_000_000))

        #expect(content.rows.count == 8)
        #expect(launcher.spawned.isEmpty, "rendering Health spawned \(launcher.spawned)")
        #expect(store.doctor == nil, "the section acquired a doctor outcome nobody asked for")
    }

    /// The last-update reading costs nothing, and the doctor run is the only
    /// thing that spawns.
    @MainActor
    @Test("Health owns exactly two acquisitions, and only one of them spawns")
    func healthOwnsExactlyTwoAcquisitions() async {
        let launcher = CompositionLauncher()
        let doctor = StubDoctorSource(outcome: .issues(HealthFixtures.evidence(warnings: 2)))
        let marker = HealthFixtures.homebrewRoots.prefix
            .appendingPathComponent(".git")
            .appendingPathComponent("FETCH_HEAD")
        let store = HealthStore(
            doctorSource: doctor,
            metadataAccess: StubFileMetadataAccess(
                answers: [marker.path: .read(Date(timeIntervalSince1970: 1_900_000))]
            )
        )

        store.readLastUpdate(roots: HealthFixtures.homebrewRoots, now: Date(timeIntervalSince1970: 2_000_000))
        #expect(store.lastUpdate == .read(Date(timeIntervalSince1970: 1_900_000)))
        #expect(doctor.runCount == 0, "reading the checkout's age ran doctor")
        #expect(launcher.spawned.isEmpty, "the invocation-free reading invoked something")

        await store.runDoctor(using: HealthFixtures.installation)
        #expect(doctor.runCount == 1)
        #expect(store.doctor?.evidence?.warningCount == 2)
    }

    /// Structural. The two claims a behavioural test cannot make: that no view in
    /// the Health group **acquires** by being rendered, and that the store holds
    /// no seam beyond its two.
    ///
    /// Not "no `.task` at all" — the section does carry exactly one, and it
    /// rebuilds the pure projection when the inputs change. `HealthProjection.build`
    /// takes one value and a date, so there is no seam in its scope to reach. What
    /// is forbidden is a `.task` that *acquires*: a doctor run nobody asked for, a
    /// scan, a preview, a measurement or a refresh.
    @Test("No Health .task acquires anything, and the store holds only its two seams")
    func noHealthTaskAcquiresAnythingAndTheStoreHoldsOnlyItsTwoSeams() throws {
        let group = try HealthSources.load()
        #expect(group.count >= 5, "the Health group read as \(group.map(\.name))")
        #expect(group.contains { $0.name == "HealthStore.swift" })
        #expect(group.contains { $0.name == "HealthView.swift" })

        var blocks: [String] = []
        for source in group {
            blocks.append(contentsOf: HealthSources.taskBlocks(in: source.code))
        }
        // The anchor: the extractor really found the one `.task` that exists.
        #expect(blocks.count == 1, "found \(blocks.count) `.task` blocks in the Health group")
        #expect(blocks.first?.contains("health.project") == true)

        for block in blocks {
            for acquisition in [
                "runDoctor", "readLastUpdate", "startPreview", "refresh", "scan(", "measure", "sync"
            ] {
                #expect(
                    block.contains(acquisition) == false,
                    "a Health `.task` reaches \(acquisition); rendering must acquire nothing"
                )
            }
        }
        // The violation control, or the sweep above passes against an extractor
        // that recognises nothing.
        let offender = HealthSources.taskBlocks(in: ".task { await health.runDoctor(using: installation) }")
        #expect(offender.count == 1)
        #expect(offender.first?.contains("runDoctor") == true)

        let store = try #require(group.first { $0.name == "HealthStore.swift" }?.code)
        // The two seams it is allowed to hold…
        #expect(store.contains("DoctorSourcing"))
        #expect(store.contains("FileMetadataAccess"))
        // …and everything a third acquisition would have to name.
        for forbidden in [
            "ProcessLaunching", "URLSession", "CatalogStore", "SecurityStore", "InstalledStore",
            "DiskUsageStore", "CleanupStore", "Timer", "Task.sleep", "while true", "AsyncTimerSequence"
        ] {
            #expect(store.contains(forbidden) == false, "HealthStore reaches for \(forbidden)")
        }
    }

    /// The doctor run is user-initiated, so nothing in the composition root may
    /// call it (SH7).
    @Test("The composition root injects the two seams and runs doctor from nowhere")
    func theCompositionRootInjectsTheSeamsAndRunsDoctorFromNowhere() throws {
        let app = try HealthSources.appSource(named: "cellarApp.swift")
        #expect(app.contains("HealthStore("), "the doctor source and update reader are not composed once")
        #expect(app.contains("BrewDoctorSource"))
        #expect(app.contains("SystemFileMetadataAccess"))
        #expect(app.contains("runDoctor") == false, "the composition root runs doctor without being asked")
    }

    // MARK: - 10.6 — the copy is a constant, and the caveat cannot be dropped

    @Test("Every user-facing Health string is a named constant, not a body literal")
    func everyUserFacingHealthStringIsANamedConstant() throws {
        let group = try HealthSources.load()
        for source in group where source.name != "HealthCopy.swift" {
            let literals = HealthSources.textLiterals(in: source.code)
            #expect(
                literals.isEmpty,
                "\(source.name) renders body literals \(literals); 10.5 puts the copy in HealthCopy"
            )
        }
        // The anchor: the extractor really does find one when there is one.
        #expect(HealthSources.textLiterals(in: #"Text("Health score")"#) == ["Health score"])
    }

    @Test("The run-doctor copy says it re-measures and claims no repair")
    func theRunDoctorCopySaysItReMeasuresAndClaimsNoRepair() {
        let copy = (HealthCopy.runDoctorTitle + " " + HealthCopy.runDoctorExplanation).lowercased()
        #expect(copy.contains("re-measure") || copy.contains("re-measures"))
        for forbidden in ["fix", "repair", "resolve"] {
            #expect(copy.contains(forbidden) == false, "the run-doctor copy claims to \(forbidden)")
        }
        // And the de-emphasis carries Homebrew's own framing rather than Cellar's
        // opinion of it.
        #expect(HealthCopy.doctorDeEmphasis.contains("help the Homebrew maintainers"))
        #expect(HealthCopy.doctorDeEmphasis.contains("debugging"))
    }

    @Test("The breakdown names every input, its weight and its points")
    func theBreakdownNamesEveryInputItsWeightAndItsPoints() throws {
        for input in HealthInput.allCases {
            #expect(HealthCopy.inputName(input).isEmpty == false)
        }
        #expect(HealthCopy.answeredWeight(65).contains("65"))
        #expect(HealthCopy.answeredWeight(65).contains("100"))
        #expect(HealthCopy.nothingScored.isEmpty == false)
    }

    /// The number and its unknowns are read off **one value**, so the caveat
    /// cannot be dropped in the view layer.
    @Test("The rendered score carries its unknowns from one value")
    func theRenderedScoreCarriesItsUnknownsFromOneValue() throws {
        let complete = HealthScoring.score(HealthInputs(
            Dictionary(uniqueKeysWithValues: HealthInput.allCases.map { ($0, HealthSignal.answered(1.0)) })
        ))
        let rendered = HealthScorePresentation(complete)
        #expect(rendered.headline == "100")
        #expect(rendered.caveat == nil)
        #expect(rendered.contributions.count == HealthInput.allCases.count)

        var partialSignals = Dictionary(
            uniqueKeysWithValues: HealthInput.allCases.map { ($0, HealthSignal.answered(1.0)) }
        )
        partialSignals[.vulnerable] = .unknown(.notCovered)
        let withGap = HealthScorePresentation(HealthScoring.score(HealthInputs(partialSignals)))
        #expect(withGap.headline == "100", "a perfect number over incomplete inputs is still the number")
        #expect(withGap.caveat != nil, "a 100 with an unknown rendered as complete")
        #expect(withGap.unknowns.count == 1)
        #expect(withGap.unknowns.first?.contains(HealthCopy.inputName(.vulnerable)) == true)

        let nothing = HealthScorePresentation(HealthScoring.score(HealthInputs([:])))
        #expect(nothing.headline == HealthCopy.nothingScored)
        #expect(nothing.headline != "0")
        #expect(nothing.headline != "100")
        #expect(nothing.contributions.isEmpty)
        #expect(nothing.unknowns.count == HealthInput.allCases.count)
    }

    /// One initialiser, one argument. There is no second way to build the
    /// presentation, so there is no way to build one that renders a number
    /// without the unknowns that came with it.
    @Test("The score presentation is unbuildable without the whole score state")
    func theScorePresentationIsUnbuildableWithoutTheWholeScoreState() throws {
        let source = try #require(try HealthSources.load().first { $0.name == "HealthScorePresentation.swift" }?.code)
        let initialisers = source
            .split(separator: "\n")
            .filter { $0.contains("init(") }
        #expect(initialisers.count == 1, "\(initialisers.count) initialisers; one of them takes less than the state")
        #expect(initialisers.first?.contains("HealthScoreState") == true)
        // No accessor anywhere hands out the number on its own.
        #expect(source.contains("var value: Int") == false)
    }

    // MARK: - Helpers

    private static func result(partial: Bool) -> SecurityScanResult {
        SecurityScanResult(
            revision: SecurityScanRevision(ordinal: 1),
            entries: [],
            provenance: ScanProvenance(
                scannedAt: Date(timeIntervalSince1970: 1_000_000),
                matcherVersion: 1,
                mappingRevision: 1
            ),
            isPartial: partial
        )
    }
}

/// Reads `cellar/Health/` off disk.
///
/// The `AppSecuritySources` idiom narrowed to one group, because every claim in
/// this file is about that group and a repository-wide sweep would let a Health
/// rule pass on the strength of an unrelated file.
nonisolated enum HealthSources {
    static func load() throws -> [AppSecuritySources.Source] {
        let directory = AppSecuritySources.directory.appendingPathComponent("Health", isDirectory: true)
        let urls = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try urls.map { url in
            AppSecuritySources.Source(
                name: url.lastPathComponent,
                code: AppSecuritySources.stripComments(from: try String(contentsOf: url, encoding: .utf8))
            )
        }
    }

    static func appSource(named name: String) throws -> String {
        AppSecuritySources.stripComments(
            from: try String(
                contentsOf: AppSecuritySources.directory.appendingPathComponent(name),
                encoding: .utf8
            )
        )
    }

    /// The body of every `.task` modifier in `code`.
    ///
    /// Brace-matched rather than line-scanned, so a multi-line block is read whole
    /// and a nested closure inside it does not end it early.
    static func taskBlocks(in code: String) -> [String] {
        var blocks: [String] = []
        var searchStart = code.startIndex

        while let marker = code.range(of: ".task", range: searchStart..<code.endIndex) {
            searchStart = marker.upperBound
            guard let open = code[marker.upperBound...].firstIndex(of: "{"),
                  let close = matchingBrace(in: code, openedAt: open)
            else { break }
            blocks.append(String(code[code.index(after: open)..<close]))
            searchStart = close
        }
        return blocks
    }

    private static func matchingBrace(in source: String, openedAt open: String.Index) -> String.Index? {
        var depth = 0
        var index = open
        var inString = false

        while index < source.endIndex {
            let character = source[index]
            if inString {
                if character == "\\" {
                    index = source.index(after: index)
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// The string literals handed straight to a `Text`, `Label` or `Button` —
    /// the ones a wording review would never find because they are not in
    /// `HealthCopy`.
    static func textLiterals(in code: String) -> [String] {
        var found: [String] = []
        for constructor in ["Text(\"", "Label(\"", "Button(\"", "ContentUnavailableView(\""] {
            var searchStart = code.startIndex
            while let opening = code.range(of: constructor, range: searchStart..<code.endIndex) {
                guard let closing = code[opening.upperBound...].firstIndex(of: "\"") else { break }
                found.append(String(code[opening.upperBound..<closing]))
                searchStart = closing
            }
        }
        return found
    }
}

/// What the outdated row says once npm can contribute, and what the score is
/// still allowed to count.
///
/// The binding decision for this capability is **copy only**: Health gains a
/// sentence and loses nothing. The score's outdated input stays Homebrew's,
/// because an npm nobody could reach would otherwise flatter the number — three
/// unchecked npm packages would silently read as three packages that are fine —
/// and an npm that *was* reached would move a number the user cannot act on from
/// this section, since the row's remediation is `brew upgrade` and always has
/// been (`system-health`: the outdated row names both sources in its copy, and
/// the score counts Homebrew only).
@Suite("Health and the npm source")
struct HealthNpmCompositionTests {
    private static let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static func browse(
        _ packages: [InstalledPackage],
        npmSource: NpmSourceAvailability = .available
    ) -> InstalledBrowse {
        InstalledBrowse(
            inventory: InstalledInventory(packages: packages),
            isAvailable: true,
            npmSource: npmSource
        )
    }

    private static func npm(_ name: String, outdated: Bool) -> InstalledPackage {
        HealthFixtures.package(
            name,
            kind: .npm,
            installed: outdated ? "5.6.0" : "5.7.0",
            offering: "5.7.0",
            outdated: outdated,
            tap: ""
        )
    }

    private static let brewInventory = [
        HealthFixtures.package("git", offering: "2.48.0", outdated: true),
        HealthFixtures.package("wget"),
        HealthFixtures.package("jq"),
        HealthFixtures.package("fd"),
    ]

    // MARK: - The row's copy

    @Test("The row announces the merged count and says npm was not checked, naming the network")
    func theRowSaysNpmWasNotChecked() throws {
        let reading = HealthComposition.outdated(
            browse: Self.browse(Self.brewInventory + [Self.npm("typescript", outdated: false)]),
            metadata: nil,
            npmFreshness: .failed(.networkUnavailable)
        )

        let summary = try #require(reading.measurement).summary
        #expect(summary.contains("1"), "the merged outdated count is missing from \(summary)")
        #expect(summary.contains("npm not checked"))
        #expect(summary.contains("network"))
        #expect(
            summary.localizedCaseInsensitiveContains("up to date") == false,
            "an unchecked npm was described as up to date"
        )
    }

    /// Triangulation: a completed check leaves the row saying only what it
    /// always said, so the disclosure above is caused by the state rather than
    /// stapled to every row.
    @Test("A completed npm check adds no not-checked disclosure")
    func aCompletedCheckAddsNoDisclosure() throws {
        let reading = HealthComposition.outdated(
            browse: Self.browse(Self.brewInventory + [Self.npm("typescript", outdated: false)]),
            metadata: nil,
            npmFreshness: .fresh([:], at: Self.checkedAt)
        )

        let summary = try #require(reading.measurement).summary
        #expect(summary.contains("npm not checked") == false)
    }

    // MARK: - The score

    @Test("Three fresh outdated npm packages change the score in neither direction")
    func theScoreIgnoresNpmInBothDirections() {
        let brewOnly = HealthComposition.outdated(
            browse: Self.browse(Self.brewInventory), metadata: nil, npmFreshness: .fresh([:], at: Self.checkedAt)
        )
        let withNpm = HealthComposition.outdated(
            browse: Self.browse(Self.brewInventory + [
                Self.npm("typescript", outdated: true),
                Self.npm("corepack", outdated: true),
                Self.npm("pnpm", outdated: true),
            ]),
            metadata: nil,
            npmFreshness: .fresh(
                [
                    "typescript": NpmOutdatedRecord(current: "5.6.0", wanted: nil, latest: "5.7.0"),
                    "corepack": NpmOutdatedRecord(current: "5.6.0", wanted: nil, latest: "5.7.0"),
                    "pnpm": NpmOutdatedRecord(current: "5.6.0", wanted: nil, latest: "5.7.0"),
                ],
                at: Self.checkedAt
            )
        )

        #expect(brewOnly.signal == withNpm.signal, "npm moved the score")
        // And the breakdown entry says which packages the number is about, so a
        // user reading 1-of-4 against a seven-package list is not left guessing.
        #expect(HealthCopy.inputName(.outdated).contains("Homebrew"))
    }

    /// The row still announces the merged number even though the score does not
    /// count it — the two are deliberately different questions, which is why the
    /// breakdown entry has to name Homebrew.
    @Test("The row's count is merged even though the score's is not")
    func theRowCountsBothWhileTheScoreCountsOne() throws {
        let reading = HealthComposition.outdated(
            browse: Self.browse(Self.brewInventory + [Self.npm("typescript", outdated: true)]),
            metadata: nil,
            npmFreshness: .fresh(
                ["typescript": NpmOutdatedRecord(current: "5.6.0", wanted: nil, latest: "5.7.0")],
                at: Self.checkedAt
            )
        )

        let summary = try #require(reading.measurement).summary
        #expect(summary.hasPrefix("2 "), "the row did not announce the merged count: \(summary)")
    }

    // MARK: - npm off

    @Test("With the source off the row and the score are the shipped ones")
    func npmOffLeavesTheRowAndScoreUnchanged() {
        let shipped = HealthComposition.outdated(
            browse: HealthFixtures.browse(Self.brewInventory), metadata: nil
        )

        for freshness in [
            NpmOutdatedState.notChecked(.notYetChecked),
            .failed(.networkUnavailable),
            .fresh([:], at: Self.checkedAt),
        ] {
            let reading = HealthComposition.outdated(
                browse: Self.browse(Self.brewInventory, npmSource: .disabled),
                metadata: nil,
                npmFreshness: freshness
            )
            #expect(reading == shipped)
        }
    }

    // MARK: - Remediation

    /// The row's button is `brew upgrade` and stays `brew upgrade`. What it
    /// leaves behind is *said*, next to the number, rather than fixed by
    /// widening a verb this capability has no business widening.
    @Test("The remediation stays Homebrew's and its copy claims nothing about npm")
    func remediationStaysHomebrewsAndClaimsNothingAboutNpm() throws {
        #expect(HealthComposition.command(for: .upgradeAll) == .mutation(.upgradeAll))
        #expect(MutationCommand.upgradeAll.displayCommand == "brew upgrade")

        let title = try #require(HealthCopy.remediationTitle(.upgradeAll))
        #expect(title.localizedCaseInsensitiveContains("npm") == false)

        // And the row discloses the gap when there is one.
        let reading = HealthComposition.outdated(
            browse: Self.browse(Self.brewInventory + [Self.npm("typescript", outdated: true)]),
            metadata: nil,
            npmFreshness: .fresh(
                ["typescript": NpmOutdatedRecord(current: "5.6.0", wanted: nil, latest: "5.7.0")],
                at: Self.checkedAt
            )
        )
        let summary = try #require(reading.measurement).summary
        #expect(summary.contains(InstalledUpdatesSummary.npmUpgradeScopeNote))
    }
}
