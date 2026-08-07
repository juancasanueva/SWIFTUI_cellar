import Catalog
import Foundation

// MARK: - Threat response: documentation-like paths
//
// A Brewfile **is evaluated Ruby**. That is not a theoretical worry: probe U8
// pointed the real `brew bundle check --file <path>` at a Brewfile whose only
// content was a `File.write`, and the marker was on disk afterwards. Any
// "read-only diff preview" implemented by asking brew runs a stranger's code.
//
// This file is the whole of Cellar's answer. It takes `Data` and returns a
// document. It has no filesystem, no subprocess, no interpreter and no network
// to reach for — not by policy, but because none of them is imported or
// referenced here, which `BrewfileSkipTests` asserts structurally. The grammar
// is line-oriented and deliberately small, and every construct outside it is a
// **counted skip**, never an interpretation (`brewfile-management` BF1, BF2,
// BF3, BF4; design DD2).

/// The only way parsing can fail as a whole.
///
/// Everything else is a skip. Refusing a whole file is reserved for the one
/// case where continuing would be a resource decision rather than a grammar
/// decision: a file so large that reading it line by line is itself the
/// problem.
public enum BrewfileParseError: Error, Sendable, Hashable {
    case tooLarge(bytes: Int, limit: Int)
}

/// Bytes in, a typed document out.
///
/// `TapDecoder`'s shape: an uninstantiable namespace with one `@concurrent`
/// static entry point, so the work runs off the main actor and the result — a
/// tree of `Sendable` value types — crosses back with no lock and no
/// `@unchecked`.
public enum BrewfileParser {

    /// Above this, the file is refused whole and parsed never.
    ///
    /// A real dump of a heavily-populated machine is about 5 KB. Eight mebibytes
    /// is three orders of magnitude of headroom and still bounds the work a
    /// hostile file can ask for.
    public static let maximumByteCount = 8 * 1024 * 1024

    /// The entry kinds a Brewfile can carry that Cellar does not install.
    ///
    /// Named rather than inferred, so a skip can say *which* kind it refused and
    /// a surface can say "3 unsupported kinds" truthfully (design D5).
    static let unsupportedEntryKinds: Set<String> = [
        "mas", "vscode", "whalebrew", "go", "cargo",
        "uv", "npm", "krew", "flatpak", "winget"
    ]

    /// The only option key the grammar accepts. Everything else refuses its
    /// entry rather than being stripped off it.
    static let trustedOptionKey = "trusted"

    @concurrent
    public static func decode(_ data: Data) async throws(BrewfileParseError) -> BrewfileDocument {
        guard data.count <= maximumByteCount else {
            throw .tooLarge(bytes: data.count, limit: maximumByteCount)
        }

        var entries: [BrewfileEntry] = []
        var skips: [BrewfileSkip] = []

        for (offset, lineBytes) in Self.lines(of: data).enumerated() {
            let lineNumber = offset + 1
            // Decoded per line, so one bad sequence costs one line rather than
            // the whole file (BF2).
            guard let raw = String(data: lineBytes, encoding: .utf8) else {
                skips.append(
                    BrewfileSkip(
                        lineNumber: lineNumber,
                        rawLine: String(decoding: lineBytes, as: UTF8.self),
                        reason: .undecodableBytes
                    )
                )
                continue
            }
            switch Self.outcome(for: raw, lineNumber: lineNumber) {
            case .ignored: continue
            case .entry(let entry): entries.append(entry)
            case .skip(let skip): skips.append(skip)
            }
        }

        return BrewfileDocument(entries: entries, skips: skips)
    }

    // MARK: - One line

    enum LineOutcome {
        /// A blank line or a whole-line comment: no entry, and **not** a skip.
        case ignored
        case entry(BrewfileEntry)
        case skip(BrewfileSkip)
    }

    static func outcome(for raw: String, lineNumber: Int) -> LineOutcome {
        func refuse(_ reason: BrewfileSkipReason) -> LineOutcome {
            .skip(BrewfileSkip(lineNumber: lineNumber, rawLine: raw, reason: reason))
        }

        let code = Self.strippingTrailingComment(from: raw)
            .trimmingCharacters(in: .whitespaces)
        guard code.isEmpty == false else { return .ignored }

        let keyword = Self.leadingIdentifier(of: code)
        guard let kind = EntryKeyword(rawValue: keyword) else {
            return unsupportedEntryKinds.contains(keyword)
                ? refuse(.unsupportedEntryKind(keyword))
                : refuse(.unrecognisedLine)
        }

        // A trailing `if`/`unless` is Ruby, and the condition is never
        // evaluated — so the line is refused identically on every host (D6).
        guard Self.trailingConditional(in: code) == false else {
            return refuse(.rubyConditional)
        }

        let remainder = String(code.dropFirst(keyword.count))
        guard let arguments = Self.arguments(in: remainder) else {
            return refuse(.unrecognisedLine)
        }
        return Self.entry(kind: kind, arguments: arguments, lineNumber: lineNumber, raw: raw)
            ?? refuse(.unrecognisedLine)
    }

    enum EntryKeyword: String {
        case tap
        case brew
        case cask
    }

    /// Builds the entry, or hands back a refusal shaped as a skip.
    ///
    /// Returns `nil` only when the line's *structure* is wrong; a wrong **name**
    /// or a wrong **option** produces its own named skip rather than a generic
    /// one, because "we could not read this line" and "we will not install what
    /// this line asks for" are different things to tell a user.
    static func entry(
        kind: EntryKeyword,
        arguments: [Argument],
        lineNumber: Int,
        raw: String
    ) -> LineOutcome? {
        func refuse(_ reason: BrewfileSkipReason) -> LineOutcome {
            .skip(BrewfileSkip(lineNumber: lineNumber, rawLine: raw, reason: reason))
        }

        var positionals: [String] = []
        var claim: BrewfileTrustClaim?

        for argument in arguments {
            switch argument {
            case .positional(let literal):
                guard let value = Self.literalContents(of: literal) else { return nil }
                positionals.append(value)
            case .option(let key, let value):
                guard key == trustedOptionKey else { return refuse(.unsupportedOption(key)) }
                claim = Self.trustClaim(from: value)
            }
        }

        guard let name = positionals.first else { return nil }

        switch kind {
        case .tap:
            guard positionals.count <= 2 else { return nil }
            guard Self.isRepresentableToken(name), let tap = TapName(name) else {
                return refuse(.unrepresentableName)
            }
            // Pure construction, for display only: the URL never reaches argv,
            // because `TapCommand.addTap` names the tap and nothing else.
            let url = positionals.count == 2 ? URL(string: positionals[1]) : nil
            return .entry(
                BrewfileEntry(kind: .tap(tap, url: url), lineNumber: lineNumber, trustedClaim: claim)
            )

        case .brew:
            guard positionals.count == 1 else { return nil }
            guard Self.isRepresentableToken(name), let formula = FormulaID(name: name) else {
                return refuse(.unrepresentableName)
            }
            return .entry(
                BrewfileEntry(kind: .formula(formula), lineNumber: lineNumber, trustedClaim: claim)
            )

        case .cask:
            guard positionals.count == 1 else { return nil }
            guard Self.isRepresentableToken(name), let cask = CaskID(name: name) else {
                return refuse(.unrepresentableName)
            }
            return .entry(
                BrewfileEntry(kind: .cask(cask), lineNumber: lineNumber, trustedClaim: claim)
            )
        }
    }

    // MARK: - Names

    /// The characters a Homebrew token is actually spelled with, plus `/` for a
    /// tap prefix.
    ///
    /// This is **narrower** than `MutationName.isSafe` and deliberately so: PM9
    /// says a file-sourced name is subject to exactly the shipped rules *and to
    /// no weaker ones*, and a stricter rule at the file boundary is not a
    /// weaker one. `isSafe` is unchanged and remains the single gate every call
    /// site shares; this is the grammar's own answer to "is that token even a
    /// literal we accept", which is what turns a backtick or a `$(…)` into a
    /// **named refusal** rather than a name.
    ///
    /// Verified against the captured dump: every one of its 79 names passes,
    /// including `gcc@11`, `python@3.12`, `font-iosevka-term-nerd-font` and
    /// `gentleman-programming/tap/engram`.
    static func isRepresentableToken(_ token: String) -> Bool {
        // Ruby interpolation is not a literal. `"#{ENV['HOME']}/x"` must never
        // be admitted as the name it would have become had it been evaluated.
        guard token.contains("#{") == false else { return false }
        return token.allSatisfy { character in
            guard character.isASCII else { return false }
            return character.isLetter
                || character.isNumber
                || "@._-+/".contains(character)
        }
    }

    // MARK: - Line splitting

    /// Splits on the newline **byte**, before any decoding, so a line whose
    /// bytes are not UTF-8 is still a line rather than a decoding failure for
    /// everything after it.
    static func lines(of data: Data) -> [Data] {
        guard data.isEmpty == false else { return [] }
        var lines: [Data] = []
        var current = Data()
        for byte in data {
            if byte == 0x0A {
                lines.append(Self.trimmingCarriageReturn(current))
                current = Data()
            } else {
                current.append(byte)
            }
        }
        if current.isEmpty == false { lines.append(Self.trimmingCarriageReturn(current)) }
        return lines
    }

    private static func trimmingCarriageReturn(_ line: Data) -> Data {
        line.last == 0x0D ? line.dropLast() : line
    }

    // MARK: - Lexing

    /// The leading run of identifier characters. Empty for a line that does not
    /// start with one at all — a backtick command, a `$(…)` substitution — which
    /// is exactly what makes those `unrecognisedLine` rather than anything more
    /// interesting.
    static func leadingIdentifier(of code: String) -> String {
        String(code.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
    }

    /// Cuts a trailing `#` comment, respecting quotes.
    ///
    /// Quote-aware because a dump line can carry `#` inside a literal — and
    /// because `"#{…}"` must survive to be *refused as a name* rather than
    /// silently truncated into a valid-looking one.
    static func strippingTrailingComment(from line: String) -> String {
        var scanner = QuoteScanner()
        for (index, character) in zip(line.indices, line) {
            if character == "#", scanner.isInsideString == false {
                return String(line[line.startIndex..<index])
            }
            scanner.consume(character)
        }
        return line
    }

    /// Whether a trailing Ruby conditional modifier is present at top level.
    static func trailingConditional(in code: String) -> Bool {
        var scanner = QuoteScanner()
        var word = ""
        for character in code {
            if scanner.isInsideString == false, character.isLetter {
                word.append(character)
            } else {
                if scanner.isInsideString == false, word == "if" || word == "unless" { return true }
                word = ""
            }
            scanner.consume(character)
        }
        return word == "if" || word == "unless"
    }

    enum Argument: Sendable, Equatable {
        /// A quoted string literal, **including** its quotes.
        case positional(String)
        case option(key: String, value: String)
    }

    /// Splits the text after the keyword into top-level arguments.
    ///
    /// `nil` when the text is not an argument list at all — an unquoted method
    /// call such as `Foo.bar`, which the grammar has no reading for.
    static func arguments(in text: String) -> [Argument]? {
        var results: [Argument] = []
        for piece in Self.topLevelComponents(of: text) {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }   // a trailing comma
            if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") {
                guard trimmed.hasSuffix(String(trimmed.first!)), trimmed.count >= 2 else { return nil }
                results.append(.positional(trimmed))
                continue
            }
            guard let separator = Self.optionSeparator(in: trimmed) else { return nil }
            let key = String(trimmed[trimmed.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            guard key.isEmpty == false,
                  key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
            else { return nil }
            results.append(.option(key: key, value: value))
        }
        return results.isEmpty ? nil : results
    }

    /// The `:` that separates an option key from its value, at top level.
    private static func optionSeparator(in text: String) -> String.Index? {
        var scanner = QuoteScanner()
        for (index, character) in zip(text.indices, text) {
            if character == ":", scanner.isInsideString == false, scanner.depth == 0 { return index }
            scanner.consume(character)
        }
        return nil
    }

    /// Splits on commas that are outside quotes, braces and brackets.
    static func topLevelComponents(of text: String) -> [String] {
        var scanner = QuoteScanner()
        var components: [String] = []
        var current = ""
        for character in text {
            if character == ",", scanner.isInsideString == false, scanner.depth == 0 {
                components.append(current)
                current = ""
            } else {
                current.append(character)
            }
            scanner.consume(character)
        }
        components.append(current)
        return components
    }

    /// The contents of a quoted literal, or `nil` when it is not one.
    static func literalContents(of literal: String) -> String? {
        guard let quote = literal.first, quote == "\"" || quote == "'" else { return nil }
        guard literal.count >= 2, literal.last == quote else { return nil }
        return String(literal.dropFirst().dropLast())
    }

    // MARK: - `trusted:` (BF5)

    /// Reads the option's shape. It records **nothing**: the value is retained
    /// for display and attributed to the file's author, and no code path
    /// anywhere consults it before confirming, spawning or disclosing.
    static func trustClaim(from value: String) -> BrewfileTrustClaim? {
        let raw = "\(trustedOptionKey): \(value)"
        if value == "true" { return BrewfileTrustClaim(scope: .everything, rawOption: raw) }
        guard value.hasPrefix("{") else { return nil }
        return BrewfileTrustClaim(
            scope: .named(
                formulae: Self.namedList(in: value, keys: ["formula", "formulae"]),
                casks: Self.namedList(in: value, keys: ["cask", "casks"]),
                commands: Self.namedList(in: value, keys: ["command", "commands"])
            ),
            rawOption: raw
        )
    }

    /// Every quoted literal that follows one of `keys` inside the hash.
    ///
    /// Deliberately shallow: the value is display-only, so an exotic nesting
    /// costs a less detailed claim rather than a misparse of the line it sits
    /// on. What matters for the requirement is that the option cannot corrupt
    /// the entry and cannot be mistaken for a name.
    private static func namedList(in hash: String, keys: [String]) -> [String] {
        for key in keys {
            guard let start = hash.range(of: "\(key):") else { continue }
            let tail = hash[start.upperBound...]
            guard let open = tail.firstIndex(of: "["), let close = tail[open...].firstIndex(of: "]")
            else {
                // A single value rather than an array.
                let piece = tail.prefix { $0 != "," && $0 != "}" }
                let literal = piece.trimmingCharacters(in: .whitespaces)
                return Self.literalContents(of: literal).map { [$0] } ?? []
            }
            return Self.topLevelComponents(of: String(tail[tail.index(after: open)..<close]))
                .compactMap { Self.literalContents(of: $0.trimmingCharacters(in: .whitespaces)) }
        }
        return []
    }
}

/// Tracks whether the scanner is inside a string literal and how deep it is in
/// braces and brackets.
///
/// One small state machine, shared by the four places that need to know, so
/// "outside quotes" means the same thing to the comment stripper, the
/// conditional detector, the comma splitter and the option splitter. Single
/// quotes inside a double-quoted literal — `"#{ENV['HOME']}/x"` — are not
/// openers, which is exactly the case that would otherwise desynchronise the
/// whole line.
struct QuoteScanner {
    private var quote: Character?
    private(set) var depth = 0

    var isInsideString: Bool { quote != nil }

    mutating func consume(_ character: Character) {
        if let open = quote {
            if character == open { quote = nil }
            return
        }
        switch character {
        case "\"", "'": quote = character
        case "{", "[", "(": depth += 1
        case "}", "]", ")": depth = max(0, depth - 1)
        default: break
        }
    }
}
