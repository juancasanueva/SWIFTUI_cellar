import Foundation
import Testing

/// Reads `Sources/Catalog/` off disk.
///
/// Textual by necessity — a structural claim about what a file does *not*
/// contain cannot be made by importing it — and textual by intent: the claim is
/// about the source a reviewer reads. Same idiom the `SecurityKit` prohibition
/// scans use.
enum CatalogSources {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Catalog")

    /// One file's code with `//` and `/* */` comments removed, so a prohibition
    /// *described* in a doc comment is never mistaken for one *violated* in
    /// code. The files scanned here name every forbidden token in their own
    /// documentation, so without stripping the guard would fail on prose.
    static func code(of relativePath: String) throws -> String {
        let url = directory.appendingPathComponent(relativePath)
        let text = try String(contentsOf: url, encoding: .utf8)
        return stripComments(from: text)
    }

    static func swiftFileNames() throws -> [String] {
        try FileManager.default
            .subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
    }

    /// The positive anchor every scan runs before asserting an absence.
    ///
    /// Without it, a moved target or a typo in the path would make every
    /// prohibition below pass while proving nothing at all.
    static func assertAnchored(_ code: String, expecting token: String) {
        #expect(code.isEmpty == false, "the scan read an empty file")
        #expect(
            code.contains(token),
            "the scan read no file containing \(token), so it read nothing real"
        )
    }

    static func stripComments(from source: String) -> String {
        var result = ""
        var index = source.startIndex
        var inString = false
        var inBlockComment = false

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index) < source.endIndex
                ? source[source.index(after: index)]
                : nil

            if inBlockComment {
                if character == "*", next == "/" {
                    inBlockComment = false
                    index = source.index(index, offsetBy: 2)
                    continue
                }
                index = source.index(after: index)
                continue
            }
            if inString {
                if character == "\\", next != nil {
                    result.append(character)
                    result.append(next!)
                    index = source.index(index, offsetBy: 2)
                    continue
                }
                if character == "\"" { inString = false }
                result.append(character)
                index = source.index(after: index)
                continue
            }
            if character == "\"" {
                inString = true
                result.append(character)
                index = source.index(after: index)
                continue
            }
            if character == "/", next == "*" {
                inBlockComment = true
                index = source.index(index, offsetBy: 2)
                continue
            }
            if character == "/", next == "/" {
                while index < source.endIndex, source[index] != "\n" {
                    index = source.index(after: index)
                }
                continue
            }
            result.append(character)
            index = source.index(after: index)
        }
        return result
    }
}

/// Every stored-property label a value exposes, recursively.
///
/// Reflection and not a hand-written list on purpose: a hand-written list would
/// keep passing on the day someone adds the field it was written to forbid.
enum ExposedFields {
    static func labels(of value: Any, depth: Int = 0) -> [String] {
        guard depth < 8 else { return [] }
        var found: [String] = []
        for child in Mirror(reflecting: value).children {
            if let label = child.label { found.append(label) }
            found.append(contentsOf: labels(of: child.value, depth: depth + 1))
        }
        return found
    }

    /// Every `String` value reachable from `value`, so an assertion can prove a
    /// path or command was not merely un-labelled but genuinely not carried.
    static func strings(of value: Any, depth: Int = 0) -> [String] {
        guard depth < 8 else { return [] }
        var found: [String] = []
        if let string = value as? String { found.append(string) }
        for child in Mirror(reflecting: value).children {
            found.append(contentsOf: strings(of: child.value, depth: depth + 1))
        }
        return found
    }
}
