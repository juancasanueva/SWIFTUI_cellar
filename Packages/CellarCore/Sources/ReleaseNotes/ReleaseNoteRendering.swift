import Foundation

// MARK: - What did not survive as formatting

/// A construct this build showed as literal text rather than as formatting.
///
/// Reported rather than silently swallowed, because "we could not render your
/// table" and "there was no table" look identical in a sheet and mean different
/// things. A surface that knows a table degraded can say so; one that does not
/// will present a wall of pipes as though it were prose.
public enum UnsupportedMarkdown: String, Sendable, Hashable, Codable, CaseIterable {
    /// A GFM pipe table. CommonMark has no tables.
    case table
    /// `- [ ]` / `- [x]`. CommonMark renders the brackets literally.
    case taskList
    /// `~~text~~`. Not a CommonMark construct.
    case strikethrough
    /// `@handle`. GitHub links these; nothing else does.
    case mention
    /// A URL written bare, without `<>` or `[](…)`. GFM autolinks these.
    case bareAutolink
    /// `![alt](url)`. Deliberately degraded rather than rendered: an image in a
    /// release body is a **remote fetch**, and a release body is attacker-authored
    /// text. The alt text survives so the reader knows something was there.
    case image
}

// MARK: - The prepared value

/// A release body, ready to present.
///
/// `blocks` rather than one `AttributedString` because parsing is block-wise: a
/// construct the parser cannot handle costs its own paragraph's formatting and
/// not the note. Joining them here would throw that away.
public struct RenderedReleaseNote: Sendable, Hashable {
    public let blocks: [AttributedString]
    /// Constructs this build showed as literal text rather than formatting.
    public let degradedConstructs: Set<UnsupportedMarkdown>
    /// The total-failure fallback: every block was presented as raw text because
    /// the parser could make nothing of them.
    public let renderedAsPlainText: Bool

    public init(
        blocks: [AttributedString],
        degradedConstructs: Set<UnsupportedMarkdown>,
        renderedAsPlainText: Bool
    ) {
        self.blocks = blocks
        self.degradedConstructs = degradedConstructs
        self.renderedAsPlainText = renderedAsPlainText
    }

    /// The whole note as plain characters, for a surface that wants to search or
    /// copy it.
    public var plainText: String {
        blocks.map { String($0.characters) }.joined(separator: "\n")
    }
}

// MARK: - The renderer

/// Turns a release body into something presentable, without ever failing and
/// without ever becoming a fetch.
///
/// Foundation only — no SwiftUI — so every rule here is testable without a view,
/// and so no view is the thing deciding what is safe to render.
public enum ReleaseNoteRenderer {
    public nonisolated static func render(_ body: String) -> RenderedReleaseNote {
        let degraded = degradedConstructs(in: body)
        // Images are neutralised **before** parsing. `AttributedString` would
        // otherwise carry an `imageURL` attribute that a view is entitled to
        // fetch, and a release body is attacker-authored text.
        let neutralised = neutralisingImages(in: body)

        let rawBlocks = blocks(of: neutralised)
        guard rawBlocks.isEmpty == false else {
            return RenderedReleaseNote(
                blocks: [], degradedConstructs: degraded, renderedAsPlainText: false
            )
        }

        var parsed: [AttributedString] = []
        var failures = 0
        for block in rawBlocks {
            if let attributed = attributed(block) {
                parsed.append(withOnlyBrowsableLinks(attributed))
            } else {
                // The block is still shown, as its own raw text. Dropping it
                // would delete something the author wrote.
                parsed.append(AttributedString(block))
                failures += 1
            }
        }

        return RenderedReleaseNote(
            blocks: parsed,
            degradedConstructs: degraded,
            renderedAsPlainText: failures == parsed.count
        )
    }

    /// A URL a view may hand to the workspace opener, and `nil` for everything
    /// else.
    ///
    /// The `CaskInspection.browsableDownloadURL` allowlist, reused rather than
    /// reinvented: `javascript:`, `file:`, `data:` and every other scheme must
    /// never reach a `Link`, and a scheme nobody thought about is refused by not
    /// being on the list.
    ///
    /// A refused value is not dropped. The caller renders the text as selectable
    /// text instead of as a link, so the author's words survive and only the
    /// action is withheld.
    public nonisolated static func browsableLink(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              browsableSchemes.contains(scheme),
              url.host()?.isEmpty == false
        else { return nil }
        return url
    }

    /// Exhaustive on purpose.
    private static let browsableSchemes: Set<String> = ["http", "https"]

    // MARK: - Blocks

    /// Splits on blank lines, which is CommonMark's own block boundary.
    ///
    /// Block-wise parsing is what turns "one unsupported construct blanked the
    /// note" into "one unsupported construct lost its own paragraph's
    /// formatting". Whole-body parsing has no such failure containment.
    private nonisolated static func blocks(of body: String) -> [String] {
        body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private nonisolated static func attributed(_ block: String) -> AttributedString? {
        try? AttributedString(
            markdown: block,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: false,
                interpretedSyntax: .full,
                // One malformed span costs its own formatting rather than the
                // whole block.
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )
    }

    // MARK: - Links

    /// Strips every link the allowlist refuses, leaving its text intact.
    ///
    /// This is not belt-and-braces. `AttributedString(markdown:)` happily parses
    /// `[click](javascript:alert(1))` and attaches the destination as a `.link`
    /// attribute, and SwiftUI's `Text` hands a `.link` to the workspace opener.
    /// A release body is attacker-authored text, so the check cannot live at the
    /// view — a second view rendering the same value would have to remember it.
    ///
    /// The **text** survives. Only the action is withheld, which is the same
    /// bargain `CaskInspection.browsableDownloadURL` already strikes: the
    /// published value stays visible and selectable, and nothing follows it for
    /// you.
    private nonisolated static func withOnlyBrowsableLinks(
        _ attributed: AttributedString
    ) -> AttributedString {
        var sanitised = attributed
        for run in attributed.runs {
            guard let link = run.link else { continue }
            if browsableLink(link.absoluteString) == nil {
                sanitised[run.range].link = nil
            }
        }
        return sanitised
    }

    // MARK: - Images

    /// Rewrites `![alt](url)` to its alt text.
    ///
    /// The URL is discarded entirely rather than carried as an inert attribute,
    /// because "inert" is a property of today's view code and this is a property
    /// of the value. A prepared note that contains no remote URL cannot be made
    /// to fetch one by a future `Text` that learns to.
    private nonisolated static func neutralisingImages(in body: String) -> String {
        guard let expression = imageExpression else { return body }
        return expression.stringByReplacingMatches(
            in: body,
            range: NSRange(body.startIndex..., in: body),
            withTemplate: "$1"
        )
    }

    // MARK: - Detection

    /// What the platform renderer will not interpret, found in the **source**
    /// text rather than inferred from the parsed output.
    ///
    /// Source-side on purpose: after parsing, a degraded table and a paragraph
    /// that happens to contain pipes are the same thing, and the information
    /// needed to tell them apart has already been lost.
    private nonisolated static func degradedConstructs(in body: String) -> Set<UnsupportedMarkdown> {
        var found: Set<UnsupportedMarkdown> = []
        let lines = body.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // A table is a delimiter row, not merely a pipe: `a | b` in prose is
            // not a table, and a row of dashes and pipes is nothing else.
            if trimmed.hasPrefix("|"),
               trimmed.contains("-"),
               trimmed.replacingOccurrences(of: " ", with: "")
                   .allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" }) {
                found.insert(.table)
            }

            if let marker = taskListExpression,
               marker.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                found.insert(.taskList)
            }
        }

        if matches(strikethroughExpression, in: body) { found.insert(.strikethrough) }
        if matches(mentionExpression, in: body) { found.insert(.mention) }
        if matches(imageExpression, in: body) { found.insert(.image) }
        if hasBareAutolink(body) { found.insert(.bareAutolink) }

        return found
    }

    /// A URL written bare, outside `<>` and outside a `[](…)` destination.
    ///
    /// The exclusion is what stops every ordinary Markdown link from being
    /// reported as a degraded autolink, which would make the report useless by
    /// firing on almost every release note ever written.
    private nonisolated static func hasBareAutolink(_ body: String) -> Bool {
        guard let expression = urlExpression else { return false }
        let range = NSRange(body.startIndex..., in: body)

        for match in expression.matches(in: body, range: range) {
            guard let found = Range(match.range, in: body) else { continue }
            let before = found.lowerBound == body.startIndex
                ? nil
                : body[body.index(before: found.lowerBound)]
            // `](https://…` is a link destination; `<https://…` is an explicit
            // autolink the parser handles. Neither is a bare one.
            if before == "(" || before == "<" { continue }
            return true
        }
        return false
    }

    private nonisolated static func matches(_ expression: NSRegularExpression?, in body: String) -> Bool {
        guard let expression else { return false }
        return expression.firstMatch(
            in: body, range: NSRange(body.startIndex..., in: body)
        ) != nil
    }

    // MARK: - Expressions

    // Built once. `NSRegularExpression` is thread-safe for matching, and these
    // patterns are compile-time constants that cannot fail to compile — the
    // optionals exist only because the initialiser is throwing, and a `nil` here
    // degrades to "reported nothing" rather than to a crash.
    private nonisolated(unsafe) static let imageExpression = try? NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\([^)]*\)"#
    )
    private nonisolated(unsafe) static let taskListExpression = try? NSRegularExpression(
        pattern: #"^[-*+]\s+\[[ xX]\]\s"#
    )
    private nonisolated(unsafe) static let strikethroughExpression = try? NSRegularExpression(
        pattern: #"~~[^~]+~~"#
    )
    private nonisolated(unsafe) static let mentionExpression = try? NSRegularExpression(
        pattern: #"(^|\s)@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?"#
    )
    private nonisolated(unsafe) static let urlExpression = try? NSRegularExpression(
        pattern: #"https?://[^\s<>()\[\]]+"#
    )
}
