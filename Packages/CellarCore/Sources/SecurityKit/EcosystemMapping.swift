import Catalog
import CryptoKit
import Foundation

/// One curated pairing between a Homebrew formula and a package in an advisory
/// ecosystem.
///
/// Every field is exact and every field is required. There is no pattern, no
/// prefix, no normalisation step and no similarity score, because each of those
/// is a way for two unrelated projects that happen to share a name to be
/// reported as one.
public struct EcosystemMappingEntry: Sendable, Hashable {
    public let formulaName: String
    /// The advisory database's own ecosystem token, spelled exactly as the
    /// database spells it — `crates.io`, `PyPI`, `npm`. Case included: these are
    /// wire values, not display names.
    public let ecosystem: String
    public let ecosystemPackageName: String
    /// The upstream repository both names point at, as `host/owner/repo` and
    /// **without a scheme**.
    ///
    /// Not a URL on purpose. This target may reach exactly two hosts, both
    /// `static let` constants, and that is asserted by scanning the source for
    /// `https://` literals. Provenance is documentation; a string that is not a
    /// URL cannot become a request by accident, and the guard stays a simple
    /// fact rather than an allow-list with exceptions.
    public let sharedUpstream: String
    /// Why this pairing is believed to be the same software, in a sentence a
    /// reviewer can disagree with.
    public let provenance: String

    public init(
        formulaName: String,
        ecosystem: String,
        ecosystemPackageName: String,
        sharedUpstream: String,
        provenance: String
    ) {
        self.formulaName = formulaName
        self.ecosystem = ecosystem
        self.ecosystemPackageName = ecosystemPackageName
        self.sharedUpstream = sharedUpstream
        self.provenance = provenance
    }
}

/// What the table can say about one installed package.
///
/// The `notCovered` half lives here rather than in the matcher because this is
/// where the fact is actually known: the table is the only thing that can say
/// "absent", and the kind is decided before a lookup is even worth doing. The
/// matcher composes this result; it does not re-derive it.
public enum EcosystemMappingResult: Sendable, Hashable {
    case mapped(EcosystemMappingEntry)
    case notCovered(NotCoveredReason)
}

/// The curated formula-to-ecosystem table.
///
/// **Compiled data, not a resource.** A Swift literal is compile-checked, needs
/// no bundle plumbing inside a library target, and has no runtime decode failure
/// mode — a JSON resource would add a way for the entire discovery step to
/// vanish at launch because a file did not copy.
///
/// ## Why it is small
///
/// Probe U1 measured real curated coverage at roughly 3–5% of an inventory, and
/// measured that the alternative — matching by name — is dominated by identity
/// collisions. Homebrew's `curl` and RubyGems' `curl` are unrelated software
/// sharing four letters; `coreutils` names both the GNU tools and an unrelated
/// Rust rewrite. Every one of those would produce a confident finding against
/// software the user never installed, and a user has no way to tell such a
/// finding from a real one.
///
/// A single-digit table against a 159-formula machine is therefore the
/// **correct** size. A table that had grown to hundreds would mean somebody
/// started guessing, and `theTableIsSingleDigit` fails when that happens.
///
/// ## Why the revision has a fingerprint
///
/// The advisory cache invalidates on `revision`, so a corrected table can never
/// be masked by a fresh-looking entry — but only if the constant actually moves
/// when the table does. `revisionFingerprint` is recomputed on every test run,
/// so editing an entry without bumping the revision fails the suite. It is the
/// same discipline `probe-manifest.txt` applies to the captured fixtures,
/// applied to the one piece of curated data that is compiled in rather than
/// captured.
public enum EcosystemMapping {
    /// Bump **together with** `revisionFingerprint` whenever `entries` changes.
    public static let revision = 1

    /// The fingerprint of `entries` at `revision`.
    public static let revisionFingerprint =
        "34ff0434282560fbff35b23e7b53e702f4223f96d38569b5cffaad0419580255"

    /// The table.
    ///
    /// Sourced from probe U1 (Engram obs 7451), which checked each candidate's
    /// upstream repository rather than its name. The two cross-language entries
    /// carry their caveat in their own provenance rather than in a comment
    /// somewhere else.
    public static let entries: [EcosystemMappingEntry] = [
        EcosystemMappingEntry(
            formulaName: "bat",
            ecosystem: "crates.io",
            ecosystemPackageName: "bat",
            sharedUpstream: "github.com/sharkdp/bat",
            provenance: """
                U1: the Homebrew formula builds this crate from the same \
                repository, and the crate is the whole program rather than a \
                library it links.
                """
        ),
        EcosystemMappingEntry(
            formulaName: "eza",
            ecosystem: "crates.io",
            ecosystemPackageName: "eza",
            sharedUpstream: "github.com/eza-community/eza",
            provenance: """
                U1: same repository, same program. The crate is published by \
                the project the formula builds.
                """
        ),
        EcosystemMappingEntry(
            formulaName: "ripgrep",
            ecosystem: "crates.io",
            ecosystemPackageName: "ripgrep",
            sharedUpstream: "github.com/BurntSushi/ripgrep",
            provenance: """
                U1: same repository, same program. The crate name and the \
                formula name coincide because both come from the project.
                """
        ),
        EcosystemMappingEntry(
            formulaName: "sd",
            ecosystem: "crates.io",
            ecosystemPackageName: "sd",
            sharedUpstream: "github.com/chmln/sd",
            provenance: """
                U1: same repository, same program. A two-letter name is exactly \
                the kind that similarity matching gets wrong, which is why this \
                one was checked against its upstream rather than assumed.
                """
        ),
        EcosystemMappingEntry(
            formulaName: "uv",
            ecosystem: "PyPI",
            ecosystemPackageName: "uv",
            sharedUpstream: "github.com/astral-sh/uv",
            provenance: """
                U1: the formula installs the same binary the PyPI distribution \
                wheels, built from the same repository at the same version.
                """
        ),
        EcosystemMappingEntry(
            formulaName: "protobuf",
            ecosystem: "PyPI",
            ecosystemPackageName: "protobuf",
            sharedUpstream: "github.com/protocolbuffers/protobuf",
            provenance: """
                U1: same repository. CAVEAT, recorded rather than hidden: the \
                formula installs the C++ runtime and compiler while the PyPI \
                distribution is the Python binding, so an advisory may apply to \
                one language surface and not the other. The finding is framed \
                as reported for PyPI/protobuf, and the version boundary keeps \
                any fix claim honest.
                """
        ),
        EcosystemMappingEntry(
            formulaName: "llhttp",
            ecosystem: "npm",
            ecosystemPackageName: "llhttp",
            sharedUpstream: "github.com/nodejs/llhttp",
            provenance: """
                U1: same repository. CAVEAT, recorded rather than hidden: the \
                formula installs the generated C library while the npm package \
                is the JavaScript and WebAssembly build. Both are produced from \
                the one parser definition, so parser-level advisories apply to \
                both, but a binding-specific one may not.
                """
        )
    ]

    // MARK: - Lookup

    /// The entry for a formula name, matched **exactly**.
    ///
    /// No case folding, no trimming, no alias resolution. Every one of those is
    /// a way for `BAT` or ` bat` to resolve to something the curator never
    /// approved.
    public static func entry(forFormula name: String) -> EcosystemMappingEntry? {
        index[name]
    }

    /// What is known about one installed package, before anything is queried.
    ///
    /// The kind is decided first and independently of the name: a cask called
    /// `bat` is `kindUnsupported`, not "mapped to the crate". Only formulae are
    /// in scope, and a cask that happens to share a formula's name must not
    /// borrow its coverage.
    public static func lookup(_ packageID: PackageID) -> EcosystemMappingResult {
        guard packageID.kind == .formula else { return .notCovered(.kindUnsupported) }
        guard let entry = entry(forFormula: packageID.name) else {
            return .notCovered(.unmapped)
        }
        return .mapped(entry)
    }

    // MARK: - Fingerprint

    /// A stable digest of a table's content.
    ///
    /// Order-independent and field-complete: entries are rendered canonically
    /// and sorted, so reordering the literal does not move the fingerprint while
    /// changing any character of any field does. Provenance is included on
    /// purpose — a mapping whose justification was quietly rewritten is a
    /// different mapping.
    public static func fingerprint(of entries: [EcosystemMappingEntry]) -> String {
        let canonical = entries
            .map { entry in
                [
                    entry.formulaName,
                    entry.ecosystem,
                    entry.ecosystemPackageName,
                    entry.sharedUpstream,
                    entry.provenance
                ].joined(separator: "\u{1F}")
            }
            .sorted()
            .joined(separator: "\u{1E}")

        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static let index: [String: EcosystemMappingEntry] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.formulaName, $0) }
    )
}
