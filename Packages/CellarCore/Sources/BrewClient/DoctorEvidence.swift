import BrewProcess
import Foundation

/// One grouped `Warning:` block.
///
/// `detail` holds the block's lines in the order they appeared, verbatim,
/// including their indentation: the captured report indents inconsistently
/// (`    gemini-cli` beside `  ruby@3.1`), so normalising it would lose
/// information brew chose to emit.
public struct DoctorWarning: Sendable, Hashable {
    /// The remainder of the `Warning: ` line. Empty is legal and recorded — with
    /// `.emptyWarningHeadline` beside it — because dropping the block would lose
    /// a warning brew actually raised.
    public let headline: String
    public let detail: [String]

    public init(headline: String, detail: [String]) {
        self.headline = headline
        self.detail = detail
    }
}

/// Something the grouping could not do cleanly. Never a failure — the evidence
/// is still produced, and `isPartial` says the grouping is incomplete.
public enum DoctorParseIssue: String, Sendable, Hashable {
    /// A `Warning: ` line whose remainder was empty.
    case emptyWarningHeadline
    /// An indented, detail-shaped line with no block open to attach it to.
    case orphanDetailLine
    /// A line whose bytes are not valid UTF-8. It survives as bytes.
    case undecodableLine
    /// The document opened no warning block and carried no ready statement, so
    /// the grammar recognised nothing in it at all. Without this case such a
    /// document would file its whole self as preamble and report zero warnings —
    /// which reads exactly like a healthy machine.
    case unrecognisedReport
}

/// Which of the two streams the payload actually arrived on.
///
/// Recorded rather than assumed. U10 measured the whole report on **stderr**
/// with one byte on stdout, and the grammar is written for that. A future brew
/// that moves the payload is then *visible in the evidence* instead of being
/// silently parsed as a clean machine.
public enum DoctorDocumentStream: String, Sendable, Hashable {
    case stdout
    case stderr
    case both
    case neither
}

public struct DoctorParserProvenance: Sendable, Hashable {
    public let parserVersion: Int
    public let documentStream: DoctorDocumentStream

    public init(parserVersion: Int = 1, documentStream: DoctorDocumentStream) {
        self.parserVersion = parserVersion
        self.documentStream = documentStream
    }
}

/// Everything one `brew doctor` run produced, raw **and** grouped (product §9
/// Q5, settled as both — D6).
///
/// The raw streams are the record and the grouping is a projection over it:
/// re-reading `rawStderr` is always possible and is unaffected by what the
/// grouping recognised. That is what makes a doctor-output change a *visible*
/// event rather than a silent one.
///
/// `rawStdout` and `rawStderr` are separate stored properties and are **never**
/// concatenated, interleaved, trimmed or folded into one another anywhere in
/// this module.
public struct DoctorEvidence: Sendable, Hashable {
    public let rawStdout: Data
    public let rawStderr: Data
    /// Non-empty, non-indented lines before the first block, in order. On the
    /// captured run this is Homebrew's own de-emphasis of its warnings, which is
    /// why the doctor input carries the lowest weight in the health score.
    public let preamble: [String]
    public let warnings: [DoctorWarning]
    /// Lines the grouping did not recognise, as **bytes**. Held undecoded so a
    /// run that is not valid UTF-8 survives with no replacement character
    /// substituted for it.
    public let unknownLines: [Data]
    public let issues: Set<DoctorParseIssue>
    /// Whether the document carried Homebrew's own clean-run sentence.
    ///
    /// This is what tells "brew said everything is fine" apart from "brew said
    /// something this grammar has never seen", from the bytes alone. Both have
    /// zero warning blocks; only one of them is good news.
    public let reportsReady: Bool
    public let provenance: DoctorParserProvenance

    public init(
        rawStdout: Data,
        rawStderr: Data,
        preamble: [String],
        warnings: [DoctorWarning],
        unknownLines: [Data],
        issues: Set<DoctorParseIssue>,
        reportsReady: Bool,
        provenance: DoctorParserProvenance
    ) {
        self.rawStdout = rawStdout
        self.rawStderr = rawStderr
        self.preamble = preamble
        self.warnings = warnings
        self.unknownLines = unknownLines
        self.issues = issues
        self.reportsReady = reportsReady
        self.provenance = provenance
    }

    /// `0` on a clean run — **present, never absent**, so "nothing was wrong"
    /// and "nothing was measured" stay distinguishable. An evidence value only
    /// exists because a document was parsed.
    public var warningCount: Int { warnings.count }

    /// Same rule, for the lines the grouping could not place.
    public var unknownLineCount: Int { unknownLines.count }

    /// Whether the grouping is incomplete. Never a failure.
    public var isPartial: Bool { !issues.isEmpty }
}

/// Why no document could be obtained **at all**.
///
/// Deliberately narrow. A run that completed and exited non-zero is never
/// unavailable: that is the ordinary "brew found warnings" answer, and it
/// carries the document (`system-health`, "A non-zero doctor exit is an ordinary
/// outcome").
///
/// `Equatable` rather than `Hashable`: `BrewProcessError` — the shipped spawn
/// fault this carries verbatim rather than re-describing — is `Equatable` only,
/// and widening a shipped `BrewProcess` type to satisfy a new consumer is the
/// wrong direction for the dependency to point.
public enum DoctorUnavailableReason: Sendable, Equatable {
    /// There is no usable `brew` to ask. Guidance, not failure.
    case brewUnavailable
    /// The spawn itself failed.
    case launchFailed(BrewProcessError)
    /// The run was cancelled.
    case cancelled
    /// The process was terminated by a signal Cellar did not send, so whatever
    /// it had written is not a complete report.
    case signalled(Int32)
}

/// The three answers a doctor run can produce.
///
/// Exactly three, and `unavailable` names **only** the cases in which no document
/// could be obtained. A completed non-zero run cannot reach it — that is the
/// whole inversion, and `DoctorSourcing`'s lack of `throws` is what enforces it
/// rather than a comment (design HD1).
public enum DoctorOutcome: Sendable, Equatable {
    case clean(DoctorEvidence)
    /// A non-zero exit. Ordinary, and it carries the document.
    case issues(DoctorEvidence)
    case unavailable(DoctorUnavailableReason)

    /// The evidence, when there is one. `nil` only for `unavailable`.
    public var evidence: DoctorEvidence? {
        switch self {
        case .clean(let evidence), .issues(let evidence): evidence
        case .unavailable: nil
        }
    }
}
