import Catalog
import Foundation

/// One package to ask OSV about.
///
/// Two versions travel together on purpose, because they answer two different
/// questions and conflating them is the failure mode this whole boundary exists
/// to prevent. `queryVersion` is what goes on the wire; `installedVersion` is
/// what the user actually has, and it is the one a fix comparison must use.
public struct AdvisoryQuery: Sendable, Hashable {
    public let packageID: PackageID
    /// Homebrew's own string for the **primary keg**, including any `_N`
    /// packaging revision.
    public let installedVersion: String
    /// The lexical upstream: `installedVersion` with a trailing `_N` removed.
    public let queryVersion: String
    public let ecosystem: String
    public let ecosystemPackageName: String

    public init(
        packageID: PackageID,
        installedVersion: String,
        queryVersion: String,
        ecosystem: String,
        ecosystemPackageName: String
    ) {
        self.packageID = packageID
        self.installedVersion = installedVersion
        self.queryVersion = queryVersion
        self.ecosystem = ecosystem
        self.ecosystemPackageName = ecosystemPackageName
    }
}

/// Either a query, or the typed reason there will not be one.
///
/// There is no third case and no optional. Every installed package produces one
/// of these, so a package cannot fall out of the scan by producing nothing.
public enum AdvisoryQueryPlan: Sendable, Hashable {
    case query(AdvisoryQuery)
    case notCovered(NotCoveredReason)

    public var query: AdvisoryQuery? {
        guard case .query(let query) = self else { return nil }
        return query
    }
}

/// How an ecosystem writes versions.
///
/// One rule per ecosystem, not one rule for everything, and the difference is
/// load-bearing. `protobuf 35.1` has two components: it is not strict SemVer and
/// it is perfectly ordinary PEP 440, and the captured `querybatch` request
/// proves OSV answers it. Gating every ecosystem on SemVer would have silently
/// dropped a package that real advisory data covers.
public enum EcosystemVersionScheme: Sendable, Hashable, CaseIterable {
    /// crates.io and npm both declare their ranges in SemVer.
    case semVer
    /// PyPI declares its ranges in PEP 440.
    case pep440

    /// The scheme for an advisory-database ecosystem token, or `nil` when the
    /// ecosystem is one this code has no rule for.
    ///
    /// `nil` is honest rather than permissive: an ecosystem nobody wrote a rule
    /// for produces `notCovered(.unsupportedVersionScheme)` instead of a query
    /// whose version the database may quietly coerce.
    public static func forEcosystem(_ ecosystem: String) -> EcosystemVersionScheme? {
        switch ecosystem {
        case "crates.io", "npm": .semVer
        case "PyPI": .pep440
        default: nil
        }
    }

    /// Whether a version string means something in this scheme.
    ///
    /// This is the *only* local decision about coverage. It does not decide
    /// whether a package is affected — that is OSV's answer, from OSV's own
    /// declared ranges. It decides whether the question can be asked at all.
    public func interprets(_ version: String) -> Bool {
        switch self {
        case .semVer: StrictSemVer.parse(version) != nil
        case .pep440: Self.isPEP440(version)
        }
    }

    // MARK: - PEP 440

    /// A deliberately conservative subset of PEP 440.
    ///
    /// Accepts an optional epoch, a dot-separated numeric release segment, an
    /// optional local segment after `+`, and an optional trailing run of
    /// recognised pre/post/dev markers. It does **not** attempt normalisation or
    /// ordering: nothing in this feature orders a PyPI version, because fix
    /// comparison runs on strict SemVer only.
    ///
    /// Being conservative is the safe direction here. A version this rejects
    /// becomes an admitted `unsupportedVersionScheme` gap; a version it wrongly
    /// accepted would become a question whose answer the database computed
    /// against a string it coerced.
    static func isPEP440(_ version: String) -> Bool {
        var rest = Substring(version.lowercased())
        guard rest.isEmpty == false else { return false }

        if let epoch = rest.firstIndex(of: "!") {
            let digits = rest.prefix(upTo: epoch)
            guard digits.isEmpty == false, digits.allSatisfy(isASCIIDigit) else { return false }
            rest = rest[rest.index(after: epoch)...]
        }

        if let local = rest.firstIndex(of: "+") {
            let segment = rest[rest.index(after: local)...]
            guard segment.isEmpty == false, segment.allSatisfy(isLocalCharacter) else {
                return false
            }
            rest = rest.prefix(upTo: local)
        }

        let releaseEnd = rest.firstIndex { isASCIIDigit($0) == false && $0 != "." } ?? rest.endIndex
        let release = rest.prefix(upTo: releaseEnd)
        let components = release.split(separator: ".", omittingEmptySubsequences: false)
        guard components.isEmpty == false,
              components.allSatisfy({ $0.isEmpty == false && $0.allSatisfy(isASCIIDigit) })
        else { return false }

        return isRecognisedSuffix(rest[releaseEnd...])
    }

    /// Zero or more `[separator]marker[separator][digits]` groups, and nothing
    /// else. This is what rejects `2026-07-16`: the release segment stops at
    /// `2026`, and `-07-16` starts with no marker this table knows.
    private static func isRecognisedSuffix(_ text: Substring) -> Bool {
        let markers = ["alpha", "beta", "preview", "post", "rev", "dev", "pre",
                       "rc", "a", "b", "c", "r"]
        var rest = text

        while rest.isEmpty == false {
            if let first = rest.first, first == "-" || first == "_" || first == "." {
                rest = rest.dropFirst()
            }
            guard let marker = markers.first(where: { rest.hasPrefix($0) }) else { return false }
            rest = rest.dropFirst(marker.count)

            if let first = rest.first, first == "-" || first == "_" || first == "." {
                rest = rest.dropFirst()
            }
            rest = rest.drop(while: isASCIIDigit)
        }
        return true
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private static func isLocalCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber
            || character == "." || character == "-" || character == "_"
    }
}

/// Turns one installed package into a query, or into the reason there is none.
///
/// ## Why this lives in `SecurityKit` and not in the app
///
/// The design puts the app-side `SecurityQueryBuilder` at the composition point
/// between `BrewClient` and this target, and it stays there — but only for the
/// part that genuinely needs both: reading `InstalledPackage.primaryKeg`. The
/// version boundary itself needs nothing from `BrewClient`, only a package
/// identity and one version string, so it lives here where `swift test` can
/// reach it. The app-side builder becomes a projection with no rules of its own,
/// which is the thin composition point the placement decision was after.
///
/// ## Only the primary keg, by shape
///
/// This function takes **one** version. There is no overload that takes a list
/// of kegs, so a second query for a second keg is not something a caller can
/// produce by accident. Which keg is primary already has an owner —
/// `InstalledDecoder.primaryKeg`, in `BrewClient` — and this target deliberately
/// cannot see it.
public enum AdvisoryQueryPlanner {
    public static func plan(
        for packageID: PackageID,
        installedVersion: String
    ) -> AdvisoryQueryPlan {
        let entry: EcosystemMappingEntry
        switch EcosystemMapping.lookup(packageID) {
        case .notCovered(let reason): return .notCovered(reason)
        case .mapped(let mapped): entry = mapped
        }

        let queryVersion = HomebrewRevision.split(installedVersion).upstream
        guard let scheme = EcosystemVersionScheme.forEcosystem(entry.ecosystem),
              scheme.interprets(queryVersion)
        else {
            return .notCovered(.unsupportedVersionScheme)
        }

        return .query(
            AdvisoryQuery(
                packageID: packageID,
                installedVersion: installedVersion,
                queryVersion: queryVersion,
                ecosystem: entry.ecosystem,
                ecosystemPackageName: entry.ecosystemPackageName
            )
        )
    }
}
