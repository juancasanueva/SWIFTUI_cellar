import Catalog
import Foundation

// MARK: - Threat response: a user-supplied file is a name source
//
// Everything in this file exists to make one sentence true by construction
// rather than by discipline: *a name read out of a Brewfile becomes a command
// only by constructing the same validated typed identity every other call site
// constructs* (package-mutation PM9).
//
// The mechanism is the shape of `BrewfileEntry.Kind`. Its three cases hold an
// already-built `TapName`, `FormulaID` or `CaskID` and no raw string anywhere.
// A name those initialisers refuse cannot be put into a case, so it is
// **unrepresentable as an entry** — the parser's only remaining option is to
// count a skip. There is no "already validated" overload to forget to use and
// no convenience constructor taking a `String`, because neither can be written
// against these cases.
//
// Two consequences follow for free. `BrewfilePlan` cannot fail and cannot emit
// free text, because by the time it sees an entry the validation already
// happened. And nothing on the import path can carry a raw file byte into argv,
// because the only values that survive parsing are typed identities
// (`brewfile-management` BF1, BF2).

/// One line of a Brewfile that Cellar could represent.
///
/// `Identifiable` by **line number**: a document is a file, a line is unique
/// within it, and two `brew "wget"` lines are therefore two selectable rows
/// rather than one deduplicated ghost. It also makes the diff's selection a
/// `Set<Int>` whose members point at something the user can actually see.
public struct BrewfileEntry: Sendable, Hashable, Identifiable {
    /// Only representable identities exist here.
    public enum Kind: Sendable, Hashable {
        case tap(TapName, url: URL?)
        case formula(FormulaID)
        case cask(CaskID)
    }

    public let kind: Kind
    public let lineNumber: Int
    /// What the line claimed with `trusted:`, when it carried one.
    ///
    /// Held on the **entry** rather than inside `Kind` because a real dump puts
    /// `trusted: true` on `brew` lines as well as on `tap` lines — 10 of them in
    /// the captured fixture. It is retained for display and confers nothing
    /// anywhere (`brewfile-management` BF5).
    public let trustedClaim: BrewfileTrustClaim?

    public init(kind: Kind, lineNumber: Int, trustedClaim: BrewfileTrustClaim? = nil) {
        self.kind = kind
        self.lineNumber = lineNumber
        self.trustedClaim = trustedClaim
    }

    public var id: Int { lineNumber }

    /// The package this entry names, for the two package kinds. `nil` for a tap,
    /// which names no package.
    public var packageID: PackageID? {
        switch kind {
        case .tap: nil
        case .formula(let formula): formula.id
        case .cask(let cask): cask.id
        }
    }

    /// The tap this entry names, for a tap entry.
    public var tapName: TapName? {
        guard case .tap(let name, _) = kind else { return nil }
        return name
    }

    /// The name as it will appear in argv — which is the same token the file
    /// contained, because it survived the typed identity unchanged.
    public var displayName: String {
        switch kind {
        case .tap(let name, _): name.rawValue
        case .formula(let formula): formula.name
        case .cask(let cask): cask.name
        }
    }
}

/// One line the grammar did not accept as an entry.
///
/// It keeps the line number **and the raw line exactly as read**, so a surface
/// can say *which* line and *why* rather than only how many
/// (`brewfile-management` BF4).
public struct BrewfileSkip: Sendable, Hashable, Identifiable {
    public let lineNumber: Int
    /// Preserved as read: no truncation, re-encoding or normalisation.
    public let rawLine: String
    public let reason: BrewfileSkipReason

    public init(lineNumber: Int, rawLine: String, reason: BrewfileSkipReason) {
        self.lineNumber = lineNumber
        self.rawLine = rawLine
        self.reason = reason
    }

    public var id: Int { lineNumber }
}

/// Why a line was skipped.
///
/// The two detail-carrying cases name the thing they refused, so "3 entries
/// skipped" can always be expanded into *which* three and *what kind*. The
/// `Category` projection is what makes the reasons distinguishable **without
/// inspecting free text**: a consumer switches on the category to group and
/// count, and reads the detail only to render.
///
/// `Category` rather than a `CaseIterable` conformance on the reason itself,
/// which associated values make impossible to synthesise. Recorded as an
/// apply-time amendment to the design's type inventory.
public enum BrewfileSkipReason: Sendable, Hashable {
    /// `mas`, `vscode`, `whalebrew`, `go`, `cargo`, `uv`, `npm`, `krew`,
    /// `flatpak`, `winget` — a kind Cellar does not install.
    case unsupportedEntryKind(String)
    /// An option key other than `trusted:`. An option changes what the author
    /// asked for; installing a stripped entry is not what they wrote.
    case unsupportedOption(String)
    /// A trailing `if`/`unless`, or any other Ruby residue. The condition is
    /// **never** evaluated, so the skip is identical on every host.
    case rubyConditional
    /// The name was refused by `TapName`, `FormulaID` or `CaskID`.
    case unrepresentableName
    /// A line the grammar does not recognise at all.
    case unrecognisedLine
    /// Bytes that are not valid UTF-8, tolerated at line granularity.
    case undecodableBytes

    public enum Category: String, Sendable, Hashable, CaseIterable {
        case unsupportedEntryKind
        case unsupportedOption
        case rubyConditional
        case unrepresentableName
        case unrecognisedLine
        case undecodableBytes
    }

    public var category: Category {
        switch self {
        case .unsupportedEntryKind: .unsupportedEntryKind
        case .unsupportedOption: .unsupportedOption
        case .rubyConditional: .rubyConditional
        case .unrepresentableName: .unrepresentableName
        case .unrecognisedLine: .unrecognisedLine
        case .undecodableBytes: .undecodableBytes
        }
    }

    /// The thing this reason named, when it named one.
    public var detail: String? {
        switch self {
        case .unsupportedEntryKind(let kind): kind
        case .unsupportedOption(let key): key
        case .rubyConditional, .unrepresentableName, .unrecognisedLine, .undecodableBytes: nil
        }
    }
}

/// A `trusted:` option, retained as **a claim made by whoever wrote the file**.
///
/// It is parsed so it can never corrupt the line it appears on or be mistaken
/// for a name; it is surfaced because it is security-relevant content and
/// hiding it would be worse than showing it; and it confers **nothing**. No tap
/// trust is recorded, no confirmation is suppressed or downgraded, no
/// disclosure is shortened, and no argv carries `trusted`, `--trusted` or
/// anything derived from it (`brewfile-management` BF5).
public struct BrewfileTrustClaim: Sendable, Hashable {
    public enum Scope: Sendable, Hashable {
        /// `trusted: true`
        case everything
        /// `trusted: { formula: …, casks: […], commands: […] }`
        case named(formulae: [String], casks: [String], commands: [String])
    }

    public let scope: Scope
    /// The option exactly as it appeared, for display.
    public let rawOption: String

    public init(scope: Scope, rawOption: String) {
        self.scope = scope
        self.rawOption = rawOption
    }

    /// The sentence a surface must show beside a claim.
    ///
    /// A named constant rather than view copy, so "the projection makes no claim
    /// that Homebrew, the tap or Cellar has granted trust" is assertable in the
    /// `swift test` inner loop rather than reviewed by eye.
    public static let attribution =
        "Claimed by this file's author. Cellar grants no trust from it."
}

/// A parsed Brewfile: what Cellar could represent, and everything it could not.
///
/// `skips` is a collection that is **empty**, never absent — "nothing was
/// skipped" and "skips were not tracked" must never be the same value (BF4).
public struct BrewfileDocument: Sendable, Hashable {
    public let entries: [BrewfileEntry]
    public let skips: [BrewfileSkip]

    public init(entries: [BrewfileEntry], skips: [BrewfileSkip]) {
        self.entries = entries
        self.skips = skips
    }

    /// No entries **and** no skips: the file said nothing at all. A file that is
    /// entirely skips is not empty — it is fully accounted for.
    public var isEmpty: Bool { entries.isEmpty && skips.isEmpty }

    /// How many lines each reason accounted for, so a surface can say
    /// "3 unsupported kinds, 1 option" without re-deriving it.
    public var skipCounts: [BrewfileSkipReason.Category: Int] {
        skips.reduce(into: [:]) { counts, skip in
            counts[skip.reason.category, default: 0] += 1
        }
    }

    /// Every `trusted:` claim the file made, in line order, for display.
    public var trustClaims: [(entry: BrewfileEntry, claim: BrewfileTrustClaim)] {
        entries.compactMap { entry in
            entry.trustedClaim.map { (entry, $0) }
        }
    }
}
