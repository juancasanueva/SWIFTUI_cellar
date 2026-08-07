import Foundation
import Testing

@testable import Catalog

/// Every weight is visible in the breakdown, and every threshold is a named
/// constant (`system-health`, "Every weight is visible in the breakdown"; design
/// HD7).
///
/// The point is not that the weights are right. It is that they are **arguable**.
/// A number nobody can decompose is authoritative by accident: the only available
/// response to it is to believe it or ignore it. So each contribution names its
/// input, the weight applied and the points that resulted, the weights recombine
/// into the reported number by the stated rule, and disagreeing with any of them
/// is a constant change rather than a redesign.
@Suite("Health weights and thresholds")
struct HealthWeightsTests {

    private static func scored(_ inputs: HealthInputs) throws -> HealthScore {
        guard case .scored(let score) = HealthScoring.score(inputs) else {
            throw Failure.notScored
        }
        return score
    }

    private enum Failure: Error { case notScored }

    private static func inputs(_ overrides: [HealthInput: HealthSignal] = [:]) -> HealthInputs {
        var signals = Dictionary(
            uniqueKeysWithValues: HealthInput.allCases.map { ($0, HealthSignal.answered(1.0)) }
        )
        for (input, signal) in overrides { signals[input] = signal }
        return HealthInputs(signals)
    }

    // MARK: - 6.5 — each contribution names its input, weight and effect

    @Test("Each contribution names its input, the weight applied and the resulting points")
    func eachContributionNamesItsInputWeightAndEffect() throws {
        let score = try Self.scored(Self.inputs([
            .outdated: .answered(0.5),
            .doctor: .answered(0.0)
        ]))

        #expect(score.contributions.count == 8)
        for contribution in score.contributions {
            #expect(contribution.weight == HealthWeights.weight(for: contribution.input))
            #expect(contribution.points == Double(contribution.weight) * contribution.health)
        }

        let outdated = try #require(score.contributions.first { $0.input == .outdated })
        #expect(outdated.weight == 20)
        #expect(outdated.health == 0.5)
        #expect(outdated.points == 10.0)

        let doctor = try #require(score.contributions.first { $0.input == .doctor })
        #expect(doctor.weight == 5)
        #expect(doctor.points == 0.0, "a zero-health input still earned points")
    }

    /// Readable **from the value**, not implicit in the arithmetic. A breakdown
    /// that only showed the points would leave the weight to be inferred by
    /// division, and a zero-health contribution would make that impossible.
    @Test("The weight is readable from a contribution even when its points are zero")
    func theWeightIsReadableEvenAtZeroPoints() throws {
        let score = try Self.scored(Self.inputs([.vulnerable: .answered(0.0)]))
        let vulnerable = try #require(score.contributions.first { $0.input == .vulnerable })

        #expect(vulnerable.points == 0.0)
        #expect(vulnerable.weight == 25, "the weight is only inferable by dividing by zero health")
    }

    @Test("The contributions recombine into the reported number by the stated rule")
    func theBreakdownAccountsForTheNumber() throws {
        let score = try Self.scored(Self.inputs([
            .outdated: .answered(0.5),
            .vulnerable: .answered(0.2),
            .cache: .answered(0.0),
            .doctor: .unknown(.notRun)
        ]))

        #expect(score.contributions.count >= 2)
        let points = score.contributions.reduce(0.0) { $0 + $1.points }
        let weight = score.contributions.reduce(0) { $0 + $1.weight }

        #expect(weight == score.answeredWeight, "the visible denominator disagrees with the breakdown")
        #expect(score.value == Int((points / Double(weight) * 100).rounded()))
        // Non-trivial: this is not the degenerate all-clean case.
        #expect(score.value < 100)
        #expect(score.value > 0)
    }

    @Test("The weights sum to 100")
    func theWeightsSumTo100() {
        let total = HealthInput.allCases.reduce(0) { $0 + HealthWeights.weight(for: $1) }

        #expect(total == 100)
        #expect(total == HealthWeights.total)
        #expect(HealthInput.allCases.count == 8)
    }

    @Test("Every input has a positive weight")
    func everyInputHasAPositiveWeight() {
        for input in HealthInput.allCases {
            #expect(HealthWeights.weight(for: input) > 0, "\(input) carries no weight at all")
        }
    }

    /// Homebrew's own manual says these warnings exist to help *its* maintainers
    /// debug a reported issue — the captured fixture's preamble says so in the
    /// report itself. Weighting them like a vulnerability would overstate what
    /// brew declines to.
    @Test("Doctor carries the lowest weight, and less than every signal about the user's own packages")
    func theDoctorWeightIsTheLowest() {
        let weights = HealthInput.allCases.map { HealthWeights.weight(for: $0) }
        let doctor = HealthWeights.weight(for: .doctor)

        #expect(doctor == weights.min(), "doctor is not the lowest weight")
        #expect(doctor == 5)

        // Lower than every signal describing the user's own packages — which is
        // what the requirement asks for, and is strict in every one of these.
        for packageSignal in [HealthInput.outdated, .vulnerable, .advisoryCoverage, .orphans, .duplicateVersions] {
            #expect(
                doctor < HealthWeights.weight(for: packageSignal),
                "doctor is weighted at least as heavily as \(packageSignal)"
            )
        }

        // `cache` ties with it at 5, deliberately and visibly: it is the other
        // row that costs the user nothing to leave alone. The tie is recorded
        // here rather than left for a reader to discover as a surprise.
        #expect(HealthWeights.weight(for: .cache) == doctor)
        #expect(weights.filter { $0 == doctor }.count == 2)
    }

    @Test("Doctor's weight is visible in the breakdown beside the outdated one")
    func theDoctorWeightIsVisibleInTheBreakdown() throws {
        let score = try Self.scored(Self.inputs([
            .doctor: .answered(0.2),
            .outdated: .answered(0.4)
        ]))

        let doctor = try #require(score.contributions.first { $0.input == .doctor })
        let outdated = try #require(score.contributions.first { $0.input == .outdated })

        #expect(doctor.weight == 5)
        #expect(outdated.weight == 20)
        #expect(doctor.weight < outdated.weight)
    }

    @Test("An unknown input is never a weighted contribution")
    func anUnknownIsNeverAContribution() throws {
        let score = try Self.scored(Self.inputs([
            .orphans: .unknown(.unknown),
            .cache: .unknown(.unmeasured)
        ]))

        #expect(score.contributions.contains { $0.input == .orphans } == false)
        #expect(score.contributions.contains { $0.input == .cache } == false)
        #expect(Set(score.unknownInputs.map(\.input)) == [.orphans, .cache])
        #expect(
            score.answeredWeight
                == 100 - HealthWeights.weight(for: .orphans) - HealthWeights.weight(for: .cache)
        )
    }

    // MARK: - 6.6 — thresholds are named constants, linear and monotonic

    @Test("Every normalisation endpoint is a named constant, not a literal in the arithmetic")
    func everyEndpointIsANamedConstant() throws {
        let source = try Self.declarations(of: "HealthScore.swift")

        for constant in [
            "outdatedShareAtZero", "vulnerableShareAtZero", "advisoryCoverageAtZero",
            "lastUpdateFreshSeconds", "lastUpdateStaleSeconds",
            "orphansAtZero", "duplicateVersionsAtZero",
            "cacheFreshBytes", "cacheStaleBytes", "doctorWarningsAtZero"
        ] {
            #expect(source.contains(constant), "the \(constant) endpoint is not a named constant")
        }
    }

    @Test("`outdated` is 1.0 at zero and 0.0 at a quarter of the inventory")
    func outdatedNormalisesLinearly() {
        #expect(HealthThresholds.outdatedHealth(outdated: 0, installed: 200) == 1.0)
        #expect(HealthThresholds.outdatedHealth(outdated: 50, installed: 200) == 0.0)
        #expect(HealthThresholds.outdatedHealth(outdated: 25, installed: 200) == 0.5)
        // Past the far end it stays at zero rather than going negative.
        #expect(HealthThresholds.outdatedHealth(outdated: 200, installed: 200) == 0.0)
        // An empty inventory has nothing outdated in it.
        #expect(HealthThresholds.outdatedHealth(outdated: 0, installed: 0) == 1.0)
    }

    @Test("`vulnerable` is 1.0 at zero and 0.0 at a twentieth of the answered packages")
    func vulnerableNormalisesLinearly() {
        #expect(HealthThresholds.vulnerableHealth(vulnerable: 0, answered: 100) == 1.0)
        #expect(HealthThresholds.vulnerableHealth(vulnerable: 5, answered: 100) == 0.0)
        // 0.6 is not representable in binary floating point, and the linear form
        // lands on 0.6000000000000001. Compared with a tolerance rather than
        // reshaping the arithmetic to flatter an equality check.
        #expect(abs(HealthThresholds.vulnerableHealth(vulnerable: 2, answered: 100) - 0.6) < 1e-9)
    }

    @Test("`advisoryCoverage` is 1.0 when everything was answered and 0.0 at half")
    func advisoryCoverageNormalisesLinearly() {
        #expect(HealthThresholds.advisoryCoverageHealth(answered: 100, total: 100) == 1.0)
        #expect(HealthThresholds.advisoryCoverageHealth(answered: 50, total: 100) == 0.0)
        #expect(HealthThresholds.advisoryCoverageHealth(answered: 75, total: 100) == 0.5)
        #expect(HealthThresholds.advisoryCoverageHealth(answered: 0, total: 100) == 0.0)
    }

    /// One day is brew's own `HOMEBREW_AUTO_UPDATE_SECS` default, so "fresh"
    /// means what Homebrew means by it rather than what Cellar decided.
    @Test("`lastUpdate` is 1.0 within a day and 0.0 at thirty days")
    func lastUpdateNormalisesLinearly() {
        let day: TimeInterval = 86_400

        #expect(HealthThresholds.lastUpdateHealth(age: 0) == 1.0)
        #expect(HealthThresholds.lastUpdateHealth(age: day) == 1.0)
        #expect(HealthThresholds.lastUpdateHealth(age: 30 * day) == 0.0)
        #expect(HealthThresholds.lastUpdateHealth(age: 60 * day) == 0.0)
        // Halfway between the two ends.
        let midpoint = HealthThresholds.lastUpdateHealth(age: day + (29 * day) / 2)
        #expect(abs(midpoint - 0.5) < 0.0001)
        #expect(HealthThresholds.lastUpdateFreshSeconds == day)
        #expect(HealthThresholds.lastUpdateStaleSeconds == 30 * day)
    }

    @Test("`orphans` and `duplicateVersions` are 1.0 at zero and 0.0 at twenty")
    func countBasedInputsNormaliseLinearly() {
        #expect(HealthThresholds.orphansHealth(count: 0) == 1.0)
        #expect(HealthThresholds.orphansHealth(count: 20) == 0.0)
        #expect(HealthThresholds.orphansHealth(count: 10) == 0.5)
        #expect(HealthThresholds.duplicateVersionsHealth(count: 0) == 1.0)
        #expect(HealthThresholds.duplicateVersionsHealth(count: 20) == 0.0)
        #expect(HealthThresholds.duplicateVersionsHealth(count: 5) == 0.75)
    }

    @Test("`cache` is 1.0 at or below one gibibyte and 0.0 at twenty")
    func cacheNormalisesLinearly() {
        let gibibyte: Int64 = 1 << 30

        #expect(HealthThresholds.cacheHealth(bytes: 0) == 1.0)
        #expect(HealthThresholds.cacheHealth(bytes: gibibyte) == 1.0)
        #expect(HealthThresholds.cacheHealth(bytes: 20 * gibibyte) == 0.0)
        #expect(HealthThresholds.cacheHealth(bytes: 100 * gibibyte) == 0.0)
        let midpoint = HealthThresholds.cacheHealth(bytes: gibibyte + (19 * gibibyte) / 2)
        #expect(abs(midpoint - 0.5) < 0.0001)
    }

    @Test("`doctor` is 1.0 at no warnings and 0.0 at ten")
    func doctorNormalisesLinearly() {
        #expect(HealthThresholds.doctorHealth(warnings: 0) == 1.0)
        #expect(HealthThresholds.doctorHealth(warnings: 10) == 0.0)
        #expect(HealthThresholds.doctorHealth(warnings: 5) == 0.5)
        #expect(HealthThresholds.doctorHealth(warnings: 2) == 0.8)
        // The captured fixture's two warnings, so the shipped number has a real
        // reference point rather than only synthetic ones.
        #expect(HealthThresholds.doctorHealth(warnings: 2) > HealthThresholds.doctorHealth(warnings: 3))
    }

    /// Monotonic per input: more of a bad thing is never better. Asserted over a
    /// sweep rather than at the endpoints, because a normalisation that inverted
    /// in the middle would pass an endpoints-only check.
    @Test("Each normalisation is monotonic across its whole range")
    func eachNormalisationIsMonotonic() {
        func nonIncreasing(_ values: [Double], _ label: String) {
            for (previous, next) in zip(values, values.dropFirst()) {
                #expect(next <= previous, "\(label) increased as the input got worse")
            }
            #expect(values.first! > values.last!, "\(label) never moves at all")
        }

        nonIncreasing((0...40).map { HealthThresholds.outdatedHealth(outdated: $0, installed: 100) }, "outdated")
        nonIncreasing((0...10).map { HealthThresholds.vulnerableHealth(vulnerable: $0, answered: 100) }, "vulnerable")
        nonIncreasing((0...25).map { HealthThresholds.orphansHealth(count: $0) }, "orphans")
        nonIncreasing((0...25).map { HealthThresholds.duplicateVersionsHealth(count: $0) }, "duplicateVersions")
        nonIncreasing((0...15).map { HealthThresholds.doctorHealth(warnings: $0) }, "doctor")
        nonIncreasing(
            (0...40).map { HealthThresholds.lastUpdateHealth(age: Double($0) * 86_400) },
            "lastUpdate"
        )
        nonIncreasing(
            (0...25).map { HealthThresholds.cacheHealth(bytes: Int64($0) * (1 << 30)) },
            "cache"
        )
        // `advisoryCoverage` improves as coverage rises, so its sweep runs the
        // other way and is asserted as non-decreasing over the same helper.
        nonIncreasing(
            (0...100).reversed().map { HealthThresholds.advisoryCoverageHealth(answered: $0, total: 100) },
            "advisoryCoverage"
        )
    }

    @Test("Every normalisation stays inside 0...1, including at absurd inputs")
    func everyNormalisationIsBounded() {
        let values = [
            HealthThresholds.outdatedHealth(outdated: 10_000, installed: 1),
            HealthThresholds.outdatedHealth(outdated: 0, installed: 0),
            HealthThresholds.vulnerableHealth(vulnerable: 10_000, answered: 0),
            HealthThresholds.advisoryCoverageHealth(answered: 500, total: 100),
            HealthThresholds.advisoryCoverageHealth(answered: 0, total: 0),
            HealthThresholds.lastUpdateHealth(age: -100_000),
            HealthThresholds.lastUpdateHealth(age: 10_000_000_000),
            HealthThresholds.orphansHealth(count: -3),
            HealthThresholds.orphansHealth(count: 10_000),
            HealthThresholds.duplicateVersionsHealth(count: 10_000),
            HealthThresholds.cacheHealth(bytes: -1),
            HealthThresholds.cacheHealth(bytes: Int64.max),
            HealthThresholds.doctorHealth(warnings: -1),
            HealthThresholds.doctorHealth(warnings: 10_000)
        ]

        for value in values {
            #expect(value >= 0.0, "a normalisation produced \(value)")
            #expect(value <= 1.0, "a normalisation produced \(value)")
            #expect(value.isNaN == false, "a normalisation produced NaN")
        }
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
