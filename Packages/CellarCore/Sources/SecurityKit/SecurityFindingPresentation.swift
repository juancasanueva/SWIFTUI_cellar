import Foundation

// MARK: - The upgrade offer

/// What an upgrade button is entitled to say.
///
/// Homebrew's version is the one that will actually be installed, and it is
/// frequently **not** the advisory's fixed version — ahead of it, behind it, or
/// packaged with a revision suffix. A button labelled with the advisory's fix
/// would promise something the command does not do, so the difference is part of
/// the value rather than a footnote somebody may forget to render.
public enum SecurityUpgradeOffer: Sendable, Hashable {
    /// Homebrew offers exactly the version the advisory declared fixed.
    case matches(version: String)
    /// Homebrew offers a different version. Both are named.
    case differs(homebrew: String, advisory: String)
    /// The advisory declared a fix and Homebrew has nothing to offer, or the
    /// advisory declared none. No button.
    case unavailable

    /// The Homebrew version an upgrade would install, or `nil` when there is
    /// nothing to offer.
    public var homebrewVersion: String? {
        switch self {
        case .matches(let version): version
        case .differs(let homebrew, _): homebrew
        case .unavailable: nil
        }
    }

    public var actionTitle: String? {
        guard let version = homebrewVersion else { return nil }
        return "Upgrade to \(version)"
    }

    /// The sentence that must appear whenever the two versions differ.
    ///
    /// Deliberately says what Homebrew offers and what the advisory declared, and
    /// stops there. It does not claim the upgrade resolves the advisory, because
    /// when Homebrew is behind the fix it does not.
    public var note: String? {
        guard case .differs(let homebrew, let advisory) = self else { return nil }
        return """
            Homebrew currently offers \(homebrew). The advisory declares its fix at \(advisory). \
            Cellar installs what Homebrew has.
            """
    }
}

extension SecurityPresentation {
    /// How one finding introduces itself.
    ///
    /// Always as a statement about the **ecosystem package**, never about the
    /// Homebrew formula. `protobuf` the formula and `protobuf` on PyPI share a
    /// name and are different things; "protobuf is vulnerable" would assert
    /// something no database said.
    public static func reportedFor(
        _ finding: VulnerabilityFinding,
        queriedVersion: String
    ) -> String {
        "Reported for \(finding.ecosystem)/\(finding.ecosystemPackageName) \(queriedVersion)"
    }

    /// What the upgrade button may offer, given what Homebrew currently has.
    public static func upgradeOffer(
        for finding: VulnerabilityFinding,
        catalogVersion: String?
    ) -> SecurityUpgradeOffer {
        guard let catalogVersion, catalogVersion.isEmpty == false else { return .unavailable }
        guard let declared = finding.declaredFixVersion, declared.isEmpty == false else {
            // Homebrew has a version and the advisory declared no fix. An upgrade
            // is still installable and there is no advisory version to differ
            // from, so there is nothing to reconcile.
            return .matches(version: catalogVersion)
        }
        return declared == catalogVersion
            ? .matches(version: catalogVersion)
            : .differs(homebrew: catalogVersion, advisory: declared)
    }

    /// What can honestly be said about the installed version against the fix.
    ///
    /// The sentences live here rather than beside `FixVersionComparison`, whose
    /// source is asserted to contain no occurrence of the word `String` at all —
    /// a comparator that cannot be called with text cannot be misapplied to
    /// Homebrew version strings, and that guard is worth more than the proximity.
    public static func fixDescription(
        _ comparison: FixVersionComparison,
        declaredFixVersion: String?
    ) -> String {
        let fix = declaredFixVersion ?? "an unstated version"
        switch comparison {
        case .fixedAtOrBefore:
            return "The fix landed at or before the installed version (\(fix))."
        case .stillAffected:
            return "The fix is published at \(fix), ahead of the installed version."
        case .noFixPublished:
            return "The advisory states that no fix is published."
        case .fixUnknown:
            return "The advisory does not say whether a fix exists."
        case .notComparable(let scheme):
            // The spec's exact wording, and deliberately no ordering verdict in
            // either direction: `1.2.3_1` against `1.2.4` has no ordering that is
            // safe to act on, and inventing one is the failure this whole version
            // boundary exists to prevent.
            return """
                A fix published at \(fix), comparison not possible for this version scheme \
                (\(Self.schemeDescription(scheme))).
                """
        }
    }

    private static func schemeDescription(_ scheme: VersionScheme) -> String {
        switch scheme {
        case .strictSemVer: "strict SemVer"
        case .homebrewRevision: "a Homebrew packaging revision"
        case .other: "not strict SemVer"
        }
    }

    // MARK: - Record locations

    /// Where the advisory itself is published, as a **location and not a URL**.
    ///
    /// No scheme, deliberately, following the same rule that keeps
    /// `EcosystemMappingEntry.provenance` schemeless: `EgressStructureTests`
    /// asserts by exact set equality that the only `https://` literals in this
    /// target are the two hosts it may *request*, and that guard is worth more
    /// than the convenience of returning a `URL` here. A string that is not a URL
    /// cannot become a request by accident. The app target adds the scheme and
    /// hands the result to the system browser, which is where opening a link
    /// belongs anyway.
    ///
    /// What is worth proving *here* is the composition — that the location is
    /// built from the advisory's own identifier and never from a name this app
    /// guessed, and that a CVE-less advisory yields no CVE link at all.
    public static func advisoryRecordLocation(_ finding: VulnerabilityFinding) -> String? {
        Self.location(host: Self.osvRecordHost, identifier: finding.advisoryID)
    }

    /// Where the CVE is published, when the advisory has one at all.
    ///
    /// `nil` for the `GHSA-`/`RUSTSEC-`/`PYSEC-` records that publish no CVE
    /// alias, rather than a link to `…/vuln/detail/` with nothing after it.
    public static func cveRecordLocation(_ finding: VulnerabilityFinding) -> String? {
        guard let cveID = finding.cveID, cveID.isEmpty == false else { return nil }
        return Self.location(host: Self.nvdRecordHost, identifier: cveID)
    }

    private static func location(host: String, identifier: String) -> String? {
        guard identifier.isEmpty == false,
              let escaped = identifier.addingPercentEncoding(
                  withAllowedCharacters: .urlPathAllowed
              )
        else { return nil }
        return host + escaped
    }

    /// The two record hosts a *person* visits, schemeless for the reason above.
    public static let osvRecordHost = "osv.dev/vulnerability/"
    public static let nvdRecordHost = "nvd.nist.gov/vuln/detail/"
}
