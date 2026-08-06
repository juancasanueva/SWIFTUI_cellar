import Foundation

/// One prerelease identifier, which SemVer orders by *kind* before content.
public enum PrereleaseIdentifier: Sendable, Hashable {
    case numeric(Int)
    case alphanumeric(String)
}

/// A version that parses as SemVer 2.0.0 and nothing else.
///
/// ## Why "strict"
///
/// This type exists to be a **type-level guarantee**, not a convenience. A
/// comparator that takes two `String`s can be pointed at two Homebrew version
/// strings, and comparing those is the exact failure `local-package-metadata`
/// forbids: `1.2.3_1` versus `1.2.4` has no ordering that is safe to act on, and
/// a wrong answer silently suppresses a real update forever.
///
/// A comparator that takes two `StrictSemVer` values cannot be misapplied,
/// because constructing one requires the string to have survived this parser.
/// The guard is therefore a fact about the signature rather than a rule someone
/// has to remember.
///
/// ## What it accepts
///
/// `MAJOR.MINOR.PATCH` with numeric identifiers that carry no leading zeros,
/// optional dot-separated prerelease identifiers after `-`, optional build
/// metadata after `+`. Measured against the real inventory captured by probe
/// gate U5, that accepts **78.6%** of installed formula versions — which is the
/// honest ceiling on the fix-comparison feature, and is asserted rather than
/// claimed.
public struct StrictSemVer: Sendable, Hashable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [PrereleaseIdentifier]
    /// Kept on the value, ignored by precedence — both of which SemVer requires.
    public let buildMetadata: String?

    public init(
        major: Int,
        minor: Int,
        patch: Int,
        prerelease: [PrereleaseIdentifier] = [],
        buildMetadata: String? = nil
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    // MARK: - Parsing

    /// Returns `nil` for anything that is not strict SemVer.
    ///
    /// `nil` is an answer here, not a failure. A version this parser refuses is
    /// a version no comparison may be attempted on, and the caller's job is to
    /// report that honestly rather than to coerce.
    public static func parse(_ version: String) -> StrictSemVer? {
        guard version.isEmpty == false else { return nil }

        var core = Substring(version)
        var buildMetadata: String?
        var prerelease: [PrereleaseIdentifier] = []

        // Build metadata first: it may itself contain hyphens, so splitting on
        // `-` before removing it would cut in the wrong place.
        if let plus = core.firstIndex(of: "+") {
            let metadata = core[core.index(after: plus)...]
            guard isValidDotSeparated(metadata, allowingLeadingZeros: true) else { return nil }
            buildMetadata = String(metadata)
            core = core.prefix(upTo: plus)
        }

        if let hyphen = core.firstIndex(of: "-") {
            let identifiers = core[core.index(after: hyphen)...]
            guard isValidDotSeparated(identifiers, allowingLeadingZeros: false) else { return nil }
            prerelease = identifiers.split(separator: ".", omittingEmptySubsequences: false)
                .map(identifier(from:))
            core = core.prefix(upTo: hyphen)
        }

        let components = core.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }

        let numbers = components.compactMap(numericIdentifier(from:))
        guard numbers.count == 3 else { return nil }

        return StrictSemVer(
            major: numbers[0],
            minor: numbers[1],
            patch: numbers[2],
            prerelease: prerelease,
            buildMetadata: buildMetadata
        )
    }

    /// A SemVer numeric identifier: digits only, and no leading zero unless the
    /// whole identifier is `0`.
    ///
    /// The leading-zero rule is what rejects `zsh-autocomplete 26.08.04` and
    /// `poppler 26.08.0` from the real inventory — versions that look numeric
    /// and are not SemVer, and would otherwise be compared with confidence.
    private static func numericIdentifier(from text: Substring) -> Int? {
        guard text.isEmpty == false, text.allSatisfy(isASCIIDigit) else { return nil }
        guard text.count == 1 || text.first != "0" else { return nil }
        return Int(text)
    }

    private static func identifier(from text: Substring) -> PrereleaseIdentifier {
        if text.allSatisfy(isASCIIDigit), let value = Int(text) { return .numeric(value) }
        return .alphanumeric(String(text))
    }

    /// Every dot-separated identifier is non-empty and alphanumeric-or-hyphen.
    ///
    /// `omittingEmptySubsequences: false` is load-bearing: it is what makes
    /// `1.2.3-rc..1` and a trailing `1.2.3-` fail rather than silently losing an
    /// empty identifier.
    private static func isValidDotSeparated(
        _ text: Substring,
        allowingLeadingZeros: Bool
    ) -> Bool {
        let identifiers = text.split(separator: ".", omittingEmptySubsequences: false)
        guard identifiers.isEmpty == false else { return false }

        return identifiers.allSatisfy { identifier in
            guard identifier.isEmpty == false else { return false }
            guard identifier.allSatisfy(isIdentifierCharacter) else { return false }
            guard allowingLeadingZeros == false, identifier.allSatisfy(isASCIIDigit) else {
                return true
            }
            return identifier.count == 1 || identifier.first != "0"
        }
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || character == "-"
    }

    // MARK: - Precedence

    /// SemVer 2.0.0 precedence.
    ///
    /// Build metadata is excluded, a prerelease precedes its own release, and
    /// prerelease identifiers order numeric before alphanumeric — which is why
    /// `1.0.0-beta.2` precedes `1.0.0-beta.11` while a lexical comparison would
    /// put them the other way round.
    public static func < (lhs: StrictSemVer, rhs: StrictSemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // A version with a prerelease has lower precedence than the release.
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return lhs.prerelease.isEmpty == false && rhs.prerelease.isEmpty
        }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            return precedes(left, right)
        }
        // All shared identifiers matched: the shorter set has lower precedence.
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func precedes(
        _ lhs: PrereleaseIdentifier,
        _ rhs: PrereleaseIdentifier
    ) -> Bool {
        switch (lhs, rhs) {
        case (.numeric(let left), .numeric(let right)): left < right
        case (.alphanumeric(let left), .alphanumeric(let right)): left < right
        // Numeric identifiers always have lower precedence than alphanumeric.
        case (.numeric, .alphanumeric): true
        case (.alphanumeric, .numeric): false
        }
    }
}
