import Foundation

/// The `brew doctor` grammar, over bytes (design HD2).
///
/// Threat response — **untrusted subprocess payload**. This is a pure function
/// over values a test can synthesise, which is what makes every hostile shape
/// reachable with no process at all: an empty headline, an orphan detail line, a
/// payload on the "wrong" stream, a byte run that is not UTF-8. Nothing here
/// takes a process, a clock or a store, so the evidence is derivable from the
/// bytes alone and two byte-identical captures are always equal.
///
/// The grammar, per line, after splitting on the newline **byte** — before any
/// decoding, so a line whose bytes are not UTF-8 is still a line rather than a
/// decoding failure for everything after it:
///
/// | Line | Outcome |
/// |---|---|
/// | bytes that are not valid UTF-8 | `unknownLines`, verbatim; `.undecodableLine` |
/// | empty (after its newline and any carriage return) | dropped — see below |
/// | `Warning: <headline>` | opens a block; `headline` is the remainder |
/// | `Warning: ` with an empty remainder | block still recorded; `.emptyWarningHeadline` |
/// | any other line while a block is open | appended to that block's `detail`, in order |
/// | an indented line with no block open | `unknownLines`; `.orphanDetailLine` |
/// | any other line with no block open | preamble, in order |
///
/// **Blank lines are the one thing dropped**, deliberately: the captured report
/// uses them as separators *inside* a block as well as between blocks, so
/// attaching them to detail would put a blank line in the middle of a rendered
/// warning, and counting them as unknown would make every real report partial.
/// "Every line is accounted for" therefore means every **non-empty** line, and
/// `DoctorParserTests.everyNonEmptyLineIsAccountedFor` holds this to it against
/// the real capture.
///
/// A **document-level** rule finishes the job, and it is the one thing here that
/// is not per-line. HD2's table assumes a first `Warning: ` exists. When none
/// does and the document carries no ready statement either, the grammar
/// recognised nothing: the accumulated preamble is reclassified into
/// `unknownLines` with `.unrecognisedReport`. Without it, a brew that rewrote its
/// doctor output would file the whole thing as "preamble", report zero warnings,
/// and read exactly like a healthy machine (`system-health`, "A wholly
/// unrecognised report is partial, not a failure").
public enum DoctorParser {
    /// Homebrew's own clean-run sentence, from `dev-cmd/doctor.rb`'s success
    /// path. Recognising it is what tells "no warnings" apart from "no idea",
    /// which are otherwise the same document: both have zero blocks.
    public static let readyStatement = "Your system is ready to brew."

    /// The prefix that opens a block. The trailing space is part of it, so a
    /// line that merely begins with the word is not a headline.
    private static let warningPrefix = "Warning: "

    /// Builds the evidence off the caller's executor.
    ///
    /// `@concurrent` rather than a plain `nonisolated func`, mirroring
    /// `DiscoverContent.build` and `PackageSearchIndex.build` (M1 D2): a
    /// synchronous nonisolated call from the main actor still runs *on* it, and
    /// the caller here is the main actor. The built value crosses back with no
    /// lock — `DoctorEvidence` is `Sendable` by composition.
    @concurrent
    public static func parse(rawStdout: Data, rawStderr: Data) async -> DoctorEvidence {
        // stderr is the document (U10). stdout is walked too, and any block it
        // carries is admitted, so a future brew that moves the payload shows up
        // in the evidence rather than being parsed as clean.
        let fromStderr = walk(rawStderr)
        let fromStdout = walk(rawStdout)

        var preamble = fromStderr.preamble + fromStdout.preamble
        var unknownLines = fromStderr.unknownLines + fromStdout.unknownLines
        var issues = fromStderr.issues.union(fromStdout.issues)
        let warnings = fromStderr.warnings + fromStdout.warnings
        let reportsReady = preamble.contains { $0.text == readyStatement }

        // The document-level rule. `preamble` is only a preamble when something
        // it precedes was recognised.
        if warnings.isEmpty, !preamble.isEmpty, !reportsReady {
            unknownLines = fromStderr.reclassifiedUnknownLines + fromStdout.reclassifiedUnknownLines
            preamble = []
            issues.insert(.unrecognisedReport)
        }

        return DoctorEvidence(
            rawStdout: rawStdout,
            rawStderr: rawStderr,
            preamble: preamble.map(\.text),
            warnings: warnings,
            unknownLines: unknownLines,
            issues: issues,
            reportsReady: reportsReady,
            provenance: DoctorParserProvenance(
                documentStream: stream(stdout: fromStdout, stderr: fromStderr)
            )
        )
    }

    // MARK: - One stream

    /// One line the grammar placed, kept as both bytes and text so a
    /// reclassified preamble can go back into `unknownLines` verbatim.
    private struct PlacedLine {
        let raw: Data
        let text: String
    }

    private struct StreamParse {
        var preamble: [PlacedLine] = []
        var warnings: [DoctorWarning] = []
        var unknownLines: [Data] = []
        var issues: Set<DoctorParseIssue> = []
        /// Every non-empty line, in document order, for the unrecognised-report
        /// rule: "the whole document" must come back in the order it arrived,
        /// not preamble-then-orphans.
        var everyLine: [Data] = []

        var hasContent: Bool { !everyLine.isEmpty }
        var reclassifiedUnknownLines: [Data] { everyLine }
    }

    private static func walk(_ data: Data) -> StreamParse {
        var parse = StreamParse()
        // Index into `parse.warnings` while a block is open.
        var openBlock: Int?

        for rawLine in lines(in: data) {
            let content = stripped(rawLine)

            guard let text = String(data: content, encoding: .utf8) else {
                parse.unknownLines.append(content)
                parse.issues.insert(.undecodableLine)
                parse.everyLine.append(content)
                continue
            }
            guard text.trimmingCharacters(in: .whitespaces).isEmpty == false else { continue }

            parse.everyLine.append(content)

            if text.hasPrefix(warningPrefix) {
                let headline = String(text.dropFirst(warningPrefix.count))
                if headline.isEmpty { parse.issues.insert(.emptyWarningHeadline) }
                parse.warnings.append(DoctorWarning(headline: headline, detail: []))
                openBlock = parse.warnings.count - 1
                continue
            }

            if let index = openBlock {
                let block = parse.warnings[index]
                parse.warnings[index] = DoctorWarning(
                    headline: block.headline,
                    detail: block.detail + [text]
                )
                continue
            }

            // No block open. An indented line is detail-shaped, so it is an
            // orphan rather than preamble — which is what makes "an indented
            // line before any warning" reachable at all.
            if text.first?.isWhitespace == true {
                parse.unknownLines.append(content)
                parse.issues.insert(.orphanDetailLine)
                continue
            }

            parse.preamble.append(PlacedLine(raw: content, text: text))
        }
        return parse
    }

    private static func stream(stdout: StreamParse, stderr: StreamParse) -> DoctorDocumentStream {
        switch (stdout.hasContent, stderr.hasContent) {
        case (true, true): .both
        case (true, false): .stdout
        case (false, true): .stderr
        case (false, false): .neither
        }
    }

    // MARK: - Byte splitting

    /// Splits on the newline **byte**, before any decoding — the
    /// `CleanupParser.lines(in:)` splitter, reused for the same reason: a line
    /// whose bytes are not UTF-8 must still be a line.
    private static func lines(in data: Data) -> [Data] {
        var result: [Data] = []
        var start = data.startIndex
        for index in data.indices where data[index] == UInt8(ascii: "\n") {
            let end = data.index(after: index)
            result.append(Data(data[start..<end]))
            start = end
        }
        if start < data.endIndex { result.append(Data(data[start..<data.endIndex])) }
        return result
    }

    /// The line without its terminator. Nothing else is trimmed: leading
    /// whitespace is the grammar's own signal, and trailing whitespace is brew's.
    private static func stripped(_ rawLine: Data) -> Data {
        var content = rawLine
        if content.last == UInt8(ascii: "\n") { content.removeLast() }
        if content.last == UInt8(ascii: "\r") { content.removeLast() }
        return content
    }
}
