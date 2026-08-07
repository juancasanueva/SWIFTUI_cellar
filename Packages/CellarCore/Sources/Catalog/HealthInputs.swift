/// The eight questions the health score is an answer to.
///
/// Deliberately a **re-declared scalar vocabulary** naming no foreign type
/// (design HD6). `Catalog` has no target dependencies at all, and this is the
/// only target in the package that is dependency-free, so placing the score here
/// makes "the score can see neither brew nor advisories" a fact of the build
/// graph rather than a promise in a comment. The app target performs every
/// mapping from `DoctorOutcome`, `CoverageTotals`, `SecurityScanState`,
/// `CleanupOrphans`, `DiskUsageSnapshot`, `InstalledBrowse` and
/// `HomebrewLastUpdate` into a `HealthSignal`.
///
/// Same "re-declare rather than import" discipline `ReleaseNotes` uses for its
/// consent and credential seams.
public enum HealthInput: String, Sendable, Hashable, CaseIterable {
    case outdated
    case vulnerable
    case advisoryCoverage
    case lastUpdate
    case orphans
    case duplicateVersions
    case cache
    case doctor
}

/// Why an input could not be answered.
///
/// Every one of these is a shape some upstream capability actually produces, and
/// every one of them is a shape that reads like good news if it is silently
/// mapped to `answered(1.0)`. They are enumerated so a row and a breakdown can
/// each **name** the reason rather than reporting a blank.
public enum HealthUnknownReason: String, Sendable, Hashable, CaseIterable {
    /// Security coverage reports the inventory is not covered.
    case notCovered
    /// A source was unavailable — no network, no credential, a refused scan.
    case unavailable
    /// Part of the inventory was answered and part was not.
    case partial
    /// The measurement has never been taken. Not the same as "measured zero".
    case unmeasured
    /// The measurement was attempted and failed.
    case failed
    /// The measurement was cancelled.
    case cancelled
    /// The upstream value is itself an explicit unknown — `CleanupOrphans.unknown`
    /// and `CleanupReportedTotal.unknown` both have one.
    case unknown
    /// The fetch marker is not there.
    case absent
    /// The fetch marker is there and could not be read.
    case unreadable
    /// The fetch marker is dated in the future, so no age can be derived.
    case futureDated
    /// Doctor has not been run. It is user-initiated, so this is the ordinary
    /// state of a freshly opened section rather than a fault.
    case notRun
}

/// One input's answer: a normalised health, or the named reason there is none.
///
/// `answered` carries a health in `0.0...1.0` where `1.0` is perfectly healthy.
/// The normalisation happens before this point, through `HealthThresholds`, so
/// the score itself never has to know what a byte or a package is.
public enum HealthSignal: Sendable, Hashable {
    case answered(Double)
    case unknown(HealthUnknownReason)

    public var health: Double? {
        if case .answered(let health) = self { return health }
        return nil
    }

    public var unknownReason: HealthUnknownReason? {
        if case .unknown(let reason) = self { return reason }
        return nil
    }
}

/// One input that could not be answered, and why.
public struct HealthUnknown: Sendable, Hashable {
    public let input: HealthInput
    public let reason: HealthUnknownReason

    public init(input: HealthInput, reason: HealthUnknownReason) {
        self.input = input
        self.reason = reason
    }
}

/// What an answered input actually measured, for the row that renders it.
///
/// The score never needs this — it works on the normalised health alone — but a
/// row that can only say "0.6 healthy" is useless, and a row that invents "0
/// vulnerable" for a scan nobody ran is worse than useless. So the app supplies
/// the sentence it measured, and the projection carries it **only** where the
/// signal was answered.
///
/// `summary` is deliberately app-authored text rather than a count and a unit:
/// `Catalog` has no idea what a byte, a keg or a CVE is, and teaching it would
/// undo exactly the dependency-free position that makes the score trustworthy.
///
/// `unanswered` is the other half of a partial answer — a scan that covered part
/// of the inventory reports both what it found and what it could not reach,
/// rather than presenting its result as covering everything.
public struct HealthMeasurement: Sendable, Hashable {
    public let summary: String
    public let unanswered: HealthUnknownReason?

    public init(summary: String, unanswered: HealthUnknownReason? = nil) {
        self.summary = summary
        self.unanswered = unanswered
    }
}

/// The single value the score is a pure function of.
///
/// Total over `HealthInput`: an input the caller did not supply is `unknown`,
/// never absent and never defaulted to healthy. There is no way to hand this
/// type a partial dictionary and have the missing entries quietly score as
/// clean.
///
/// `measurements` is display detail and is deliberately **separate** from the
/// signals: a measurement without an answered signal is not rendered, so no
/// count can ever outlive the answer it came from.
public struct HealthInputs: Sendable, Hashable {
    private let signals: [HealthInput: HealthSignal]
    private let measurements: [HealthInput: HealthMeasurement]

    public init(
        _ signals: [HealthInput: HealthSignal],
        measurements: [HealthInput: HealthMeasurement] = [:]
    ) {
        var complete: [HealthInput: HealthSignal] = [:]
        for input in HealthInput.allCases {
            complete[input] = signals[input] ?? .unknown(.unmeasured)
        }
        self.signals = complete
        self.measurements = measurements
    }

    public subscript(input: HealthInput) -> HealthSignal {
        signals[input] ?? .unknown(.unmeasured)
    }

    /// The measurement for an input, and `nil` whenever the signal was not
    /// answered — so an unanswered row has nothing to render even if a stale
    /// measurement was handed in beside it.
    public func measurement(for input: HealthInput) -> HealthMeasurement? {
        guard case .answered = self[input] else { return nil }
        return measurements[input]
    }
}

/// The remediations a health row may offer.
///
/// A closed set, and **every entry names a verb another capability already
/// ships**. This capability introduces no new mutating verb: there is no
/// `brew doctor --fix` to offer, and `brew update` is a `.mutate` that PRD §3.4
/// does not list among the dashboard's actions. `none` is a case rather than an
/// optional so a row with nothing to offer presents no control at all, instead
/// of a disabled one (`system-health`, "Remediation offers only verbs the app
/// already ships").
public enum HealthRemediation: String, Sendable, Hashable, CaseIterable {
    case upgradeAll
    case autoremove
    case cleanupCache
    /// Re-runs the measurement. It repairs nothing, and the copy that offers it
    /// says so.
    case runDoctor
    case none
}
