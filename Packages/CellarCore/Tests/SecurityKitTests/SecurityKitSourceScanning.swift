import Foundation
import Testing

/// One `SecurityKit` source file, with its comments removed.
struct SecurityKitSource: Sendable {
    let name: String
    /// The file's code with `//` line comments and `/* */` block comments
    /// stripped, so a prohibition *described* in a doc comment is never mistaken
    /// for a prohibition *violated* in code. This file's own documentation names
    /// every forbidden token; without stripping, the guard would fail on prose.
    let code: String
}

/// Reads `Sources/SecurityKit/` off disk.
///
/// Textual by necessity — a structural claim about what a target does *not*
/// contain cannot be made by importing it — and textual by intent: the claim is
/// about the source a reviewer reads.
enum SecurityKitSources {
    /// The one file permitted to write, because it owns derived cache data
    /// rather than any inspected artifact.
    static let cacheFileName = "AdvisoryCache.swift"

    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/SecurityKit")

    static func load() throws -> [SecurityKitSource] {
        let names = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()

        return try names.map { name in
            let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            return SecurityKitSource(name: name, code: stripComments(from: text))
        }
    }

    /// The positive anchor every scan runs before asserting an absence.
    ///
    /// Without this, an empty directory, a moved target or a typo in the path
    /// would make every prohibition below pass while proving nothing at all.
    static func assertAnchored(_ sources: [SecurityKitSource]) {
        #expect(sources.isEmpty == false, "the scan found no Swift file in Sources/SecurityKit")
        #expect(
            sources.contains { $0.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false },
            "every file the scan read was empty"
        )
        #expect(
            sources.contains { $0.code.contains("import Foundation") },
            "the scan read no file containing a known-present token, so it read nothing real"
        )
    }

    /// Every string literal's **contents**, in source order.
    ///
    /// Contents rather than whole literals, so an assertion can compare against
    /// the constant a source file declares rather than against a quoted form of
    /// it. Escape pairs are preserved verbatim — that is what keeps `\(` visible
    /// so an interpolated URL can be caught rather than silently unescaped away.
    static func stringLiterals(in code: String) -> [String] {
        var literals: [String] = []
        var current = ""
        var inString = false
        let characters = Array(code)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            guard inString else {
                if character == "\"" { inString = true; current = "" }
                index += 1
                continue
            }
            if character == "\\", index + 1 < characters.count {
                current.append(character)
                current.append(characters[index + 1])
                index += 2
                continue
            }
            if character == "\"" {
                literals.append(current)
                inString = false
                index += 1
                continue
            }
            current.append(character)
            index += 1
        }
        return literals
    }

    static func stripComments(from source: String) -> String {
        var stripper = CommentStripper(source: Array(source))
        return stripper.run()
    }
}

/// Removes comments while leaving string literals byte-intact.
///
/// A small state machine rather than one long loop, because the three states —
/// code, inside a string, inside a block comment — answer the same character
/// differently and reading them side by side is how the escape-pair rule below
/// stays visible.
private struct CommentStripper {
    let source: [Character]
    private var result = ""
    private var index = 0
    private var inString = false
    private var inBlockComment = false

    init(source: [Character]) {
        self.source = source
    }

    mutating func run() -> String {
        while index < source.count {
            let character = source[index]
            let next = index + 1 < source.count ? source[index + 1] : nil

            if inBlockComment {
                stepBlockComment(character, next)
            } else if inString {
                stepString(character, next)
            } else {
                stepCode(character, next)
            }
        }
        return result
    }

    private mutating func stepBlockComment(_ character: Character, _ next: Character?) {
        if character == "*", next == "/" {
            inBlockComment = false
            index += 2
            return
        }
        index += 1
    }

    private mutating func stepString(_ character: Character, _ next: Character?) {
        if character == "\\" {
            // The escape *pair* survives, both characters of it. Dropping it —
            // as this did originally — deletes `\(` from every interpolated
            // literal, which would make the no-interpolation half of the
            // two-host guard structurally unable to fire.
            result.append(character)
            if let next { result.append(next) }
            index += 2
            return
        }
        if character == "\"" { inString = false }
        result.append(character)
        index += 1
    }

    private mutating func stepCode(_ character: Character, _ next: Character?) {
        if character == "\"" {
            inString = true
            result.append(character)
            index += 1
            return
        }
        if character == "/", next == "*" {
            inBlockComment = true
            index += 2
            return
        }
        if character == "/", next == "/" {
            while index < source.count, source[index] != "\n" { index += 1 }
            return
        }
        result.append(character)
        index += 1
    }
}

extension String {
    /// Whether `token` appears as a **whole identifier**, not as a fragment of a
    /// longer one.
    ///
    /// This distinction is load-bearing, not pedantry. The threat matrix forbids
    /// the `xattr` *command-line tool* while the design mandates the `getxattr`
    /// and `listxattr` *C functions* as its read-only replacement. A naive
    /// substring scan would ban the mandated API and pass only by deleting the
    /// feature. Likewise `Process` must not match `ProcessInfo`.
    func containsIdentifier(_ token: String) -> Bool {
        guard token.isEmpty == false else { return false }
        let haystack = Array(self)
        let needle = Array(token)
        guard haystack.count >= needle.count else { return false }

        func isIdentifierCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }

        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            let before = start > 0 ? haystack[start - 1] : nil
            let after = start + needle.count < haystack.count ? haystack[start + needle.count] : nil
            let boundedBefore = before.map { isIdentifierCharacter($0) == false } ?? true
            let boundedAfter = after.map { isIdentifierCharacter($0) == false } ?? true
            if boundedBefore, boundedAfter { return true }
        }
        return false
    }
}
