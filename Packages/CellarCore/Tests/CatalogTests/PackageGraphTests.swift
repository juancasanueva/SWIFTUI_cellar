import Foundation
import Testing

/// The package graph as an asserted fact rather than a convention.
///
/// Catalog acquisition must never need a `brew` binary (catalog-sync CS1). That
/// is enforced *structurally* by `Package.swift`: the `Catalog` target declares
/// no dependency on `BrewProcess`, directly or transitively. Parsing the
/// manifest keeps the guarantee alive when a target is added between the two —
/// which is exactly what `BrewClient` does (installed-inventory II7).
@Suite("Package graph")
struct PackageGraphTests {
    @Test("The catalog target declares no dependency on the brew-process target")
    func catalogDeclaresNoBrewProcessDependency() throws {
        let graph = try Self.graph()

        let catalog = try #require(graph["Catalog"], "no `Catalog` target in the manifest")
        #expect(catalog.isEmpty)
    }

    @Test("No path through the manifest reaches brew-process from the catalog")
    func brewProcessIsUnreachableFromCatalog() throws {
        let graph = try Self.graph()

        #expect(Self.reachable(from: "Catalog", in: graph).contains("BrewProcess") == false)
    }

    /// Triangulation: the same reachability walk must actually find an edge, or
    /// the assertion above would pass against a parser that returns nothing.
    @Test("The reachability walk does find a declared brew-process edge")
    func reachabilityFindsRealEdges() throws {
        let graph = try Self.graph()
        let dependents = graph.keys.filter {
            Self.reachable(from: $0, in: graph).contains("BrewProcess")
        }

        #expect(dependents.contains("BrewProcessTests"))
        #expect(dependents.isEmpty == false)
    }

    // MARK: - The manifest

    /// `Package.swift`, located from this file rather than the working
    /// directory, so the suite is independent of where `swift test` was run.
    static let manifestURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Package.swift")

    static func graph() throws -> [String: [String]] {
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let declarations = ManifestParser.targets(in: manifest)
        #expect(declarations.count >= 4, "the manifest parser found no targets")
        return Dictionary(
            declarations.map { ($0.name, $0.dependencies) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Every target reachable from `origin`, excluding `origin` itself.
    static func reachable(from origin: String, in graph: [String: [String]]) -> Set<String> {
        var seen: Set<String> = []
        var pending = graph[origin] ?? []
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            pending.append(contentsOf: graph[next] ?? [])
        }
        return seen
    }
}

/// One target declaration as the manifest writes it.
struct ManifestTarget: Sendable, Hashable {
    let name: String
    let dependencies: [String]
}

/// Reads the declared target graph out of a `Package.swift` source file.
///
/// Textual by necessity — a test target cannot import `PackageDescription` — and
/// textual by intent: the claim under test is about what the manifest *says*,
/// which is the artifact a reviewer reads.
enum ManifestParser {
    static func targets(in manifest: String) -> [ManifestTarget] {
        let source = Array(manifest)
        return (bodies(of: ".target(", in: source) + bodies(of: ".testTarget(", in: source))
            .compactMap(target(from:))
    }

    private static func target(from body: [Character]) -> ManifestTarget? {
        guard let name = quotedValue(after: "name:", in: body) else { return nil }
        return ManifestTarget(name: name, dependencies: dependencies(in: body))
    }

    /// Every string literal inside the `dependencies:` array literal.
    ///
    /// Over-approximating on purpose: a `.product(name:package:)` entry would
    /// contribute both of its strings. A guard that errs toward reporting an
    /// edge can only fail loudly, never wave one through.
    private static func dependencies(in body: [Character]) -> [String] {
        guard let label = index(of: Array("dependencies:"), in: body),
              let open = body[label...].firstIndex(of: "[")
        else { return [] }
        let list = balanced(in: body, from: open, open: "[", close: "]")
        return literals(in: list)
    }

    private static func quotedValue(after label: String, in body: [Character]) -> String? {
        guard let start = index(of: Array(label), in: body) else { return nil }
        return literals(in: Array(body[start...])).first
    }

    /// The bodies of every `call` in `source`, parentheses balanced.
    private static func bodies(of call: String, in source: [Character]) -> [[Character]] {
        let needle = Array(call)
        var bodies: [[Character]] = []
        var cursor = source.startIndex
        while let start = index(of: needle, in: Array(source[cursor...])) {
            let open = cursor + start + needle.count - 1
            bodies.append(balanced(in: source, from: open, open: "(", close: ")"))
            cursor = open + 1
        }
        return bodies
    }

    /// The characters between `from` and its matching close delimiter.
    ///
    /// String literals are skipped so a bracket inside a quoted string cannot
    /// unbalance the scan.
    private static func balanced(
        in source: [Character],
        from start: Int,
        open: Character,
        close: Character
    ) -> [Character] {
        var depth = 0
        var index = start
        var inString = false
        while index < source.count {
            let character = source[index]
            if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == open { depth += 1 }
                if character == close {
                    depth -= 1
                    if depth == 0 { return Array(source[(start + 1)..<index]) }
                }
            }
            index += 1
        }
        return []
    }

    private static func literals(in source: [Character]) -> [String] {
        var found: [String] = []
        var current: [Character] = []
        var inString = false
        for character in source {
            if character == "\"" {
                if inString { found.append(String(current)) }
                current = []
                inString.toggle()
            } else if inString {
                current.append(character)
            }
        }
        return found
    }

    private static func index(of needle: [Character], in haystack: [Character]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return start
        }
        return nil
    }
}
