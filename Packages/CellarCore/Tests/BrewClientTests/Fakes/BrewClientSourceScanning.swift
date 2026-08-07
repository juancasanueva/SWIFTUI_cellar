import Foundation
import Testing

/// One `BrewClient` source file, with its comments removed.
struct BrewClientSource: Sendable {
    let name: String
    /// The file's code with `//` line comments and `/* */` block comments
    /// stripped, so a prohibition *described* in a doc comment is never mistaken
    /// for one *violated* in code. This package documents its forbidden tokens
    /// in prose at length; without stripping, the guards would fail on the
    /// documentation that explains them.
    let code: String
}

/// Reads `Sources/BrewClient/` off disk.
///
/// Textual by necessity — a structural claim about what a target does *not*
/// contain cannot be made by importing it — and textual by intent: the claim is
/// about the source a reviewer reads. The `ReleaseNotesSources` /
/// `SecurityKitSources` idiom, restated here because this target may not see
/// either of them.
enum BrewClientSources {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Fakes
        .deletingLastPathComponent()   // BrewClientTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // CellarCore
        .appendingPathComponent("Sources/BrewClient")

    static func load() throws -> [BrewClientSource] {
        let names = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()

        return try names.map { name in
            let text = try String(
                contentsOf: directory.appendingPathComponent(name),
                encoding: .utf8
            )
            return BrewClientSource(name: name, code: stripComments(from: text))
        }
    }

    /// The positive anchor every scan runs before asserting an absence.
    ///
    /// Without it, a moved target or a typo in the path would make every
    /// prohibition pass while proving nothing at all — the M3-0 task 8.1 lesson
    /// this project has already paid for once.
    static func assertAnchored(_ sources: [BrewClientSource]) {
        #expect(sources.isEmpty == false, "the scan found no Swift file in Sources/BrewClient")
        #expect(
            sources.contains { $0.name == "OperationCenterBulk.swift" },
            "the scan missed the file that owns the confirmation gate"
        )
        #expect(
            sources.contains { $0.code.contains("public struct AnyBrewMutation") },
            "the scan read no file containing a known-present token, so it read nothing real"
        )
    }

    static func stripComments(from source: String) -> String {
        var stripper = BrewClientCommentStripper(source: Array(source))
        return stripper.run()
    }
}

extension String {
    /// Whether `token` appears as a **whole identifier**, not as a fragment of a
    /// longer one.
    ///
    /// Load-bearing for the same reason it is in `ReleaseNotesSources`:
    /// `Process` must not match `ProcessInfo` or `BrewProcess` by accident in
    /// either direction, and `URL` must not match `URLSession`.
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

/// Removes comments while leaving string literals byte-intact.
///
/// A small state machine rather than one long loop, because the three states —
/// code, inside a string, inside a block comment — answer the same character
/// differently, and reading them side by side is how the escape-pair rule stays
/// visible.
private struct BrewClientCommentStripper {
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
            // The escape *pair* survives, both characters of it. Dropping it
            // deletes `\(` from every interpolated literal, which would make a
            // no-interpolation guard structurally unable to fire.
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
