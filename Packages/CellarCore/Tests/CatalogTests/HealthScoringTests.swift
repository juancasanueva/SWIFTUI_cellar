import Foundation
import Testing

@testable import Catalog

/// The composite score, and the two lies it is built not to tell
/// (`system-health`, "The score is computed over answered inputs only, and its
/// unknowns are inseparable from it"; design HD6, HD7, HD8 — decision D3).
///
/// A single 0–100 number is the one surface where a user cannot see a
/// substitution. `CoverageTotals` carries its own doc comment saying exactly
/// this: a summary can read "0 vulnerabilities" over an inventory nobody could
/// answer for. On a list you might notice. On a number you cannot.
///
/// So an unanswered input does **neither** of the two things it could do. It is
/// not scored as clean, which would flatter; and it is not scored as a penalty,
/// which would punish the user for a measurement Cellar failed to take. It
/// leaves both sums and is disclosed instead.
///
/// Every test here runs with no store, no clock, no filesystem and no process,
/// because the function's signature cannot accept one.
@Suite("Health scoring")
struct HealthScoringTests {

    // MARK: - Arrangement

    /// Every input answered clean. The base every test below perturbs, so a
    /// difference is always attributable to the one thing that was changed.
    private static var allClean: HealthInputs {
        HealthInputs(Dictionary(
            uniqueKeysWithValues: HealthInput.allCases.map { ($0, HealthSignal.answered(1.0)) }
        ))
    }

    private static func inputs(
        _ overrides: [HealthInput: HealthSignal] = [:]
    ) -> HealthInputs {
        var signals = Dictionary(
            uniqueKeysWithValues: HealthInput.allCases.map { ($0, HealthSignal.answered(1.0)) }
        )
        for (input, signal) in overrides { signals[input] = signal }
        return HealthInputs(signals)
    }

    private static func scored(_ inputs: HealthInputs) throws -> HealthScore {
        guard case .scored(let score) = HealthScoring.score(inputs) else {
            throw ScoringFailure.notScored
        }
        return score
    }

    private enum ScoringFailure: Error { case notScored }

    // MARK: - 6.1 — a pure function of one value

    @Test("The same inputs always produce the same score")
    func scoringIsDeterministic() throws {
        let inputs = Self.inputs([
            .outdated: .answered(0.4),
            .vulnerable: .answered(0.9),
            .cache: .unknown(.unmeasured)
        ])

        let first = try Self.scored(inputs)
        let second = try Self.scored(inputs)
        let third = try Self.scored(inputs)

        #expect(first == second)
        #expect(second == third)
        #expect(first.contributions == second.contributions)
        #expect(first.unknownInputs == second.unknownInputs)
        // Non-trivial: this is a real, mixed score rather than an empty one.
        #expect(first.contributions.count == 7)
        #expect(first.unknownInputs.count == 1)
    }

    /// The signature is the proof. Nothing that could vary between two calls can
    /// be passed in, so nothing that could vary between two calls can be read.
    @Test("The score function reaches no store, clock, filesystem, network or process")
    func theScoreFunctionReachesNoIO() throws {
        let scoring = try Self.declarations(of: "HealthScore.swift")
        let inputs = try Self.declarations(of: "HealthInputs.swift")

        // Spelled as the tokens a type is actually *reached* through rather than
        // as bare words. `cache` is one of the eight inputs and `cleanupCache`
        // is one of the remediations, so a substring scan for "Cache" would
        // report the vocabulary as an I/O dependency and prove nothing.
        for forbidden in [
            "FileManager", "URLSession", "URL(", "Process", "Date(", "Date.now",
            "DateFormatter", "ContinuousClock", "SuspendingClock",
            "CatalogStore", "CatalogFileSystem", "async ", "await ", "throws"
        ] {
            #expect(scoring.contains(forbidden) == false, "HealthScore.swift reaches \(forbidden)")
            #expect(inputs.contains(forbidden) == false, "HealthInputs.swift reaches \(forbidden)")
        }

        // The signature takes exactly one value and returns exactly one value.
        #expect(scoring.contains("static func score(_ inputs: HealthInputs) -> HealthScoreState"))
        // Positive anchor, so a scan that read nothing cannot pass silently.
        #expect(scoring.contains("HealthScoring"), "the source scan read nothing")
        #expect(inputs.contains("HealthSignal"), "the inputs scan read nothing")
    }

    /// `Catalog` has no target dependencies at all, so "the score can see neither
    /// brew nor advisories" is a fact of the build graph rather than a promise.
    /// This is the readable half of that fact.
    @Test("The health sources import nothing from the brew, security or persistence layers")
    func theHealthSourcesImportNothingForeign() throws {
        for file in ["HealthInputs.swift", "HealthScore.swift"] {
            let source = try Self.source(of: file)
            for foreign in ["BrewClient", "BrewProcess", "SecurityKit", "DiskUsage", "Persistence"] {
                #expect(source.contains("import \(foreign)") == false, "\(file) imports \(foreign)")
            }
        }
    }

    // MARK: - 6.2 — answered inputs only, in both directions

    /// The sharp test, and the one D3 exists for: hold everything else constant
    /// and flip **one** signal between its two answered ends and unknown. The
    /// unknown result must sit outside the interval the two answered ones span,
    /// in neither direction — it must not move the number at all.
    @Test(
        "An unanswered input contributes neither a penalty nor a credit",
        arguments: HealthInput.allCases
    )
    func anUnknownContributesNothingInEitherDirection(input: HealthInput) throws {
        let clean = try Self.scored(Self.inputs([input: .answered(1.0)]))
        let worst = try Self.scored(Self.inputs([input: .answered(0.0)]))
        let unknown = try Self.scored(Self.inputs([input: .unknown(.unmeasured)]))

        // The control: answering it either way genuinely moves the number, so
        // "unknown did not move it" is a statement about unknown.
        #expect(clean.value > worst.value, "\(input) does not affect the score at all")

        // Neither sum was touched: every other input was clean, so the number
        // over the answered ones is still 100.
        #expect(unknown.value == 100, "\(input) unknown moved the number to \(unknown.value)")
        #expect(unknown.value == clean.value, "an unknown \(input) was penalised")

        // And the difference is disclosed rather than deducted.
        #expect(unknown.unknownInputs.map(\.input) == [input])
        #expect(unknown.contributions.contains { $0.input == input } == false)
        #expect(clean.unknownInputs.isEmpty)
    }

    /// The same claim over a non-perfect baseline, so it cannot pass by the
    /// number happening to be pinned at 100.
    @Test("Over a mixed baseline, an unknown still moves neither sum")
    func anUnknownMovesNeitherSumOverAMixedBaseline() throws {
        let baseline = Self.inputs([
            .outdated: .answered(0.5),
            .vulnerable: .answered(0.8),
            .orphans: .answered(0.25)
        ])
        var withUnknown = [HealthInput: HealthSignal]()
        withUnknown[.outdated] = .answered(0.5)
        withUnknown[.vulnerable] = .answered(0.8)
        withUnknown[.orphans] = .answered(0.25)
        withUnknown[.cache] = .unknown(.unmeasured)

        let answered = try Self.scored(baseline)
        let unknown = try Self.scored(Self.inputs(withUnknown))

        // `cache` was clean in the baseline, so dropping it from both sums
        // *lowers* the number — it was pulling the average up. That is not a
        // penalty; it is the honest average over what was actually answered.
        #expect(answered.answeredWeight == 100)
        #expect(unknown.answeredWeight == 100 - HealthWeights.weight(for: .cache))
        #expect(unknown.contributions.contains { $0.input == .cache } == false)
        #expect(unknown.unknownInputs.map(\.input) == [.cache])

        // And the number is exactly the weighted mean over the answered set,
        // with no invented deduction anywhere in it.
        let expected = unknown.contributions.reduce(0.0) { $0 + $1.points }
            / Double(unknown.answeredWeight)
        #expect(unknown.value == Int((expected * 100).rounded()))
    }

    /// Every unknown reason, not just the convenient one. `notCovered`,
    /// `unavailable` and `partial` are the three M4 shapes that most look like
    /// good news.
    @Test(
        "Every unknown reason is recorded as unanswered, and none scores as clean",
        arguments: HealthUnknownReason.allCases
    )
    func everyUnknownReasonIsUnanswered(reason: HealthUnknownReason) throws {
        let score = try Self.scored(Self.inputs([.vulnerable: .unknown(reason)]))

        #expect(score.unknownInputs == [HealthUnknown(input: .vulnerable, reason: reason)])
        #expect(score.contributions.contains { $0.input == .vulnerable } == false)
        #expect(score.answeredWeight == 100 - HealthWeights.weight(for: .vulnerable))
        // It did not become a clean contribution under another name.
        #expect(score.contributions.allSatisfy { $0.input != .vulnerable })
    }

    // MARK: - 6.3 — the unknowns are structurally inseparable

    /// A perfect number over incomplete inputs is still incomplete. The number
    /// **may** be 100, and the result still must not read as clean.
    @Test("A 100 over an unanswered input is not reported as clean or complete")
    func aPerfectNumberOverIncompleteInputsIsNotClean() throws {
        let score = try Self.scored(Self.inputs([.doctor: .unknown(.notRun)]))

        #expect(score.value == 100)
        #expect(score.isComplete == false, "a score with an unknown reported itself complete")
        #expect(score.unknownInputs.map(\.input) == [.doctor])

        // The control: with everything answered, the same number *is* complete.
        let complete = try Self.scored(Self.allClean)
        #expect(complete.value == 100)
        #expect(complete.isComplete)
    }

    /// The number cannot be obtained without its unknowns: the only producer is
    /// `HealthScoring`, the memberwise initialiser is not public, and nothing
    /// anywhere returns a bare number.
    @Test("No constructor, projection or accessor yields the number alone")
    func nothingYieldsTheNumberAlone() throws {
        let source = try Self.declarations(of: "HealthScore.swift")

        // There is no public way to mint a score, so no caller can build one
        // whose unknowns disagree with its contributions.
        #expect(source.contains("public init(") == false, "HealthScore can be constructed by a caller")
        #expect(source.contains("fileprivate init("), "the single private producer is gone")

        // And no function yields the *score* as a bare number: every route to it
        // goes through a value carrying the unknowns.
        //
        // `HealthWeights.weight(for:)` is excluded by name, because a weight is
        // not a score: it is a published constant the breakdown renders, and
        // reading one tells you nothing about any machine's health.
        let returnsBareInt = source
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.contains("func ") && $0.contains("-> Int") }
            .filter { $0.contains("weight(for") == false }
        #expect(
            returnsBareInt.isEmpty,
            "a function yields the score as a bare Int: \(returnsBareInt.joined(separator: " | "))"
        )
        #expect(source.contains("-> HealthScoreState"), "the scoring entry point changed shape")

        // The one entry point, and it is the only `func` on `HealthScoring`.
        let scoringFunctions = source
            .split(separator: "HealthScoring {", maxSplits: 1)
            .last?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.contains("func ") } ?? []
        #expect(scoringFunctions.count == 2, "HealthScoring exposes \(scoringFunctions.count) functions")
        #expect(scoringFunctions.first?.contains("score(_ inputs: HealthInputs)") == true)
        #expect(scoringFunctions.last?.contains("private static func clamped") == true)
    }

    @Test("The unknown set travels with the value through equality and hashing")
    func theUnknownSetTravelsWithTheValue() throws {
        let withUnknown = try Self.scored(Self.inputs([.doctor: .unknown(.notRun)]))
        let complete = try Self.scored(Self.allClean)

        // Same number, different results — because the caveat is part of the
        // value rather than a second view onto it.
        #expect(withUnknown.value == complete.value)
        #expect(withUnknown != complete)
        #expect(withUnknown.hashValue != complete.hashValue)
    }

    // MARK: - 6.4 — nothing answered is not a verdict, and the number is bounded

    @Test("With nothing answered the result is unscorable, naming every input")
    func nothingAnsweredIsNotAVerdict() {
        let inputs = HealthInputs(Dictionary(
            uniqueKeysWithValues: HealthInput.allCases.map {
                ($0, HealthSignal.unknown(.unmeasured))
            }
        ))

        guard case .unscorable(let unknownInputs) = HealthScoring.score(inputs) else {
            Issue.record("an all-unknown input set produced a number")
            return
        }

        #expect(Set(unknownInputs.map(\.input)) == Set(HealthInput.allCases))
        #expect(unknownInputs.count == 8)
    }

    /// `.unscorable` carries no number at all — not a `0`, not a `100`, and no
    /// property that could be read as either.
    @Test("`unscorable` carries no number, and is neither 0 nor 100")
    func unscorableCarriesNoNumber() throws {
        let source = try Self.declarations(of: "HealthScore.swift")

        #expect(source.contains("case unscorable(unknownInputs: [HealthUnknown])"))
        // The case's payload is the unknowns and nothing else: no `value:`, no
        // default number smuggled in beside them.
        #expect(source.contains("case unscorable(unknownInputs: [HealthUnknown], value") == false)

        // And there is no way to read a number off the state without matching
        // `.scored` first.
        let state = HealthScoring.score(HealthInputs(Dictionary(
            uniqueKeysWithValues: HealthInput.allCases.map { ($0, HealthSignal.unknown(.unavailable)) }
        )))
        if case .scored = state { Issue.record("nothing answered produced a scored value") }
    }

    /// One answered signal is enough to score, which is what keeps `.unscorable`
    /// meaning "nothing at all" rather than "not everything".
    @Test("A single answered signal is scorable", arguments: HealthInput.allCases)
    func oneAnsweredSignalIsEnough(input: HealthInput) throws {
        var signals = Dictionary(
            uniqueKeysWithValues: HealthInput.allCases.map {
                ($0, HealthSignal.unknown(.unmeasured))
            }
        )
        signals[input] = .answered(0.5)

        let score = try Self.scored(HealthInputs(signals))

        #expect(score.contributions.map(\.input) == [input])
        #expect(score.answeredWeight == HealthWeights.weight(for: input))
        #expect(score.unknownInputs.count == 7)
        #expect(score.value == 50, "a lone half-health signal scored \(score.value)")
    }

    @Test(
        "The number is between 0 and 100 inclusive for any inputs that answer something",
        arguments: [0.0, 0.001, 0.25, 0.5, 0.75, 0.999, 1.0]
    )
    func theNumberIsBounded(health: Double) throws {
        let score = try Self.scored(HealthInputs(Dictionary(
            uniqueKeysWithValues: HealthInput.allCases.map { ($0, HealthSignal.answered(health)) }
        )))

        #expect(score.value >= 0)
        #expect(score.value <= 100)
        #expect(score.value == Int((health * 100).rounded()))
    }

    /// An out-of-range health is clamped rather than allowed to push the number
    /// outside its own stated bounds — the app target does the normalising, and
    /// a normalisation bug there must not become a score of 140.
    @Test("An out-of-range health is clamped into 0...1", arguments: [-5.0, -0.1, 1.1, 42.0])
    func anOutOfRangeHealthIsClamped(health: Double) throws {
        let score = try Self.scored(HealthInputs(Dictionary(
            uniqueKeysWithValues: HealthInput.allCases.map { ($0, HealthSignal.answered(health)) }
        )))

        #expect(score.value >= 0)
        #expect(score.value <= 100)
        #expect(score.value == (health < 0 ? 0 : 100))
    }

    // MARK: - Source access

    private static func source(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Catalog/\(file)"),
            encoding: .utf8
        )
    }

    private static func declarations(of file: String) throws -> String {
        try source(of: file)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
