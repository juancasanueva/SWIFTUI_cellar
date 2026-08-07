/// What each input is worth, and why.
///
/// The weights sum to 100 for readability, live as named constants, and are
/// rendered in the breakdown beside every contribution. That is the whole design
/// intent: the number is meant to be **arguable**. A weight nobody can see is
/// authoritative by accident, because the only available response to it is to
/// believe it or ignore it. Disagreeing with one of these is a constant change,
/// not a redesign.
public enum HealthWeights {
    /// The only input describing harm already present rather than housekeeping.
    public static let vulnerable = 25
    /// The app's primary verb, and the largest actionable non-harmful signal.
    public static let outdated = 20
    /// The M4 lesson given its own weight: an unanswered inventory costs points
    /// instead of being invisible.
    public static let advisoryCoverage = 15
    /// A stale Homebrew makes every other answer stale, including the outdated
    /// count.
    public static let lastUpdate = 15
    /// Real waste, fully remediable in one click, harmless if left.
    public static let orphans = 8
    /// Same class as orphans, smaller, and more often deliberate — a kept old
    /// version is a choice.
    public static let duplicateVersions = 7
    /// Pure disk, zero risk, and the one row a user may intentionally keep
    /// large.
    public static let cache = 5
    /// Homebrew's own manual says these warnings exist to help *its* maintainers
    /// debug a reported issue — the captured fixture's preamble says so in the
    /// report itself. Weighting them like a vulnerability would overstate what
    /// brew declines to. It ties with `cache` at the bottom, visibly and on
    /// purpose: both are rows a user may reasonably leave alone forever.
    public static let doctor = 5

    public static let total = 100

    public static func weight(for input: HealthInput) -> Int {
        switch input {
        case .vulnerable: vulnerable
        case .outdated: outdated
        case .advisoryCoverage: advisoryCoverage
        case .lastUpdate: lastUpdate
        case .orphans: orphans
        case .duplicateVersions: duplicateVersions
        case .cache: cache
        case .doctor: doctor
        }
    }
}

/// Where each input's health runs from `1.0` to `0.0`.
///
/// Every endpoint is a **named constant** rather than a literal buried in the
/// arithmetic, and every normalisation is linear between its two ends, clamped
/// into `0...1`, and monotonic. Reading this type should be enough to argue with
/// any of it.
///
/// The app target calls these to build a `HealthSignal.answered(_:)`; the score
/// itself never learns what a byte or a package is.
public enum HealthThresholds {
    /// `outdated`: perfect at none, worst when a quarter of the inventory is
    /// behind.
    public static let outdatedShareAtZero = 0.25
    /// `vulnerable`: perfect at none, worst at a twentieth of the **answered**
    /// packages — answered, because a share of an inventory nobody scanned is
    /// not a share of anything.
    public static let vulnerableShareAtZero = 0.05
    /// `advisoryCoverage`: perfect when every package was answered, worst when
    /// half were.
    public static let advisoryCoverageAtZero = 0.5
    /// `lastUpdate`: fresh within a day. Brew's own `HOMEBREW_AUTO_UPDATE_SECS`
    /// default, so "fresh" means what Homebrew means by it.
    public static let lastUpdateFreshSeconds: Double = 86_400
    /// …and worst at thirty days.
    public static let lastUpdateStaleSeconds: Double = 30 * 86_400
    public static let orphansAtZero = 20
    public static let duplicateVersionsAtZero = 20
    /// `cache`: a gibibyte is free, twenty is the far end.
    public static let cacheFreshBytes: Int64 = 1 << 30
    public static let cacheStaleBytes: Int64 = 20 * (1 << 30)
    public static let doctorWarningsAtZero = 10

    // MARK: - The normalisations

    public static func outdatedHealth(outdated: Int, installed: Int) -> Double {
        guard installed > 0 else { return 1.0 }
        return descending(
            value: Double(outdated) / Double(installed),
            best: 0,
            worst: outdatedShareAtZero
        )
    }

    public static func vulnerableHealth(vulnerable: Int, answered: Int) -> Double {
        guard answered > 0 else { return vulnerable > 0 ? 0.0 : 1.0 }
        return descending(
            value: Double(vulnerable) / Double(answered),
            best: 0,
            worst: vulnerableShareAtZero
        )
    }

    /// Ascending rather than descending: more coverage is better.
    public static func advisoryCoverageHealth(answered: Int, total: Int) -> Double {
        guard total > 0 else { return 1.0 }
        let share = min(Double(answered) / Double(total), 1.0)
        return descending(value: 1.0 - share, best: 0, worst: 1.0 - advisoryCoverageAtZero)
    }

    public static func lastUpdateHealth(age: Double) -> Double {
        descending(value: age, best: lastUpdateFreshSeconds, worst: lastUpdateStaleSeconds)
    }

    public static func orphansHealth(count: Int) -> Double {
        descending(value: Double(count), best: 0, worst: Double(orphansAtZero))
    }

    public static func duplicateVersionsHealth(count: Int) -> Double {
        descending(value: Double(count), best: 0, worst: Double(duplicateVersionsAtZero))
    }

    public static func cacheHealth(bytes: Int64) -> Double {
        descending(value: Double(bytes), best: Double(cacheFreshBytes), worst: Double(cacheStaleBytes))
    }

    public static func doctorHealth(warnings: Int) -> Double {
        descending(value: Double(warnings), best: 0, worst: Double(doctorWarningsAtZero))
    }

    /// The one piece of arithmetic, written once: `1.0` at or below `best`,
    /// `0.0` at or above `worst`, linear between them.
    private static func descending(value: Double, best: Double, worst: Double) -> Double {
        guard worst > best else { return value <= best ? 1.0 : 0.0 }
        if value <= best { return 1.0 }
        if value >= worst { return 0.0 }
        return 1.0 - (value - best) / (worst - best)
    }
}

/// One input's share of the number, fully decomposed.
///
/// `weight` is carried **beside** `points` rather than left to be inferred by
/// dividing, because a contribution whose health is zero has zero points and
/// division would recover nothing from it.
public struct HealthContribution: Sendable, Hashable {
    public let input: HealthInput
    public let weight: Int
    /// The normalised health in `0.0...1.0`, already clamped.
    public let health: Double
    /// `weight × health`.
    public let points: Double

    fileprivate init(input: HealthInput, health: Double) {
        self.input = input
        weight = HealthWeights.weight(for: input)
        self.health = health
        points = Double(weight) * health
    }
}

/// A computed score, and the unknowns it was computed **around**.
///
/// The unknowns are structurally inseparable from the number. The memberwise
/// initialiser is `fileprivate`, so `HealthScoring` is the only producer and no
/// caller can mint a score whose `unknownInputs` disagrees with its
/// `contributions`; and a surface reads `value` and `unknownInputs` off **one
/// value**, never two views, so the caveat cannot be dropped in the view layer.
///
/// There is deliberately no accessor anywhere in this file that returns the
/// number on its own. `HealthScoring.score` returns a `HealthScoreState`, and the
/// only way through it is to match `.scored` — at which point the unknowns are in
/// hand.
public struct HealthScore: Sendable, Hashable {
    /// `0...100` inclusive.
    public let value: Int
    /// The breakdown, one entry per **answered** input.
    public let contributions: [HealthContribution]
    /// Every input that could not be answered, with its reason.
    public let unknownInputs: [HealthUnknown]
    /// The visible denominator: the summed weight of the answered inputs.
    public let answeredWeight: Int

    fileprivate init(
        value: Int,
        contributions: [HealthContribution],
        unknownInputs: [HealthUnknown],
        answeredWeight: Int
    ) {
        self.value = value
        self.contributions = contributions
        self.unknownInputs = unknownInputs
        self.answeredWeight = answeredWeight
    }

    /// Whether every input was answered.
    ///
    /// A score with any unknown is never complete, **however few** — including
    /// one whose number is 100. There is no companion `isClean` that ignores the
    /// unknowns, because that is precisely the accessor a surface would reach for
    /// when it wanted to drop the caveat.
    public var isComplete: Bool { unknownInputs.isEmpty }
}

/// The score, or the fact that there is not one.
///
/// `.unscorable` is the `DiscoverSectionState` technique: a number nobody could
/// compute is a **case**, not a `0` and not a `100`. Both of those would be read
/// as verdicts — one catastrophic, one perfect — about a machine nothing was
/// measured on.
public enum HealthScoreState: Sendable, Hashable {
    case scored(HealthScore)
    case unscorable(unknownInputs: [HealthUnknown])
}

/// `value = round(100 × Σ_answered wᵢ·hᵢ / Σ_answered wᵢ)`.
///
/// A pure function of one value. Its signature cannot accept a store, a clock,
/// the filesystem, the network or a subprocess, and its implementation reaches
/// none — so the same inputs always produce the same score, and every rule about
/// it is testable with none of them available.
///
/// Unknown inputs leave **both** sums (decision D3). They neither flatter nor
/// punish: scoring an unknown as clean would tell the user their machine is
/// healthier than anyone knows, and scoring it as a penalty would punish them for
/// a measurement Cellar failed to take. Both are lies, so the unknown is
/// disclosed instead.
public enum HealthScoring {
    public static func score(_ inputs: HealthInputs) -> HealthScoreState {
        var contributions: [HealthContribution] = []
        var unknownInputs: [HealthUnknown] = []

        // `allCases` order, so the breakdown is stable and readable rather than
        // dictionary-ordered.
        for input in HealthInput.allCases {
            switch inputs[input] {
            case .answered(let health):
                contributions.append(
                    HealthContribution(input: input, health: clamped(health))
                )
            case .unknown(let reason):
                unknownInputs.append(HealthUnknown(input: input, reason: reason))
            }
        }

        // Nothing answered is not a verdict.
        guard contributions.isEmpty == false else {
            return .unscorable(unknownInputs: unknownInputs)
        }

        let answeredWeight = contributions.reduce(0) { $0 + $1.weight }
        let points = contributions.reduce(0.0) { $0 + $1.points }
        let value = Int((points / Double(answeredWeight) * 100).rounded())

        return .scored(HealthScore(
            value: value,
            contributions: contributions,
            unknownInputs: unknownInputs,
            answeredWeight: answeredWeight
        ))
    }

    /// The app target does the normalising, and a normalisation bug there must
    /// not become a score of 140.
    private static func clamped(_ health: Double) -> Double {
        guard health.isNaN == false else { return 0 }
        return min(max(health, 0), 1)
    }
}
