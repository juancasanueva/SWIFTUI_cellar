import Foundation
import Testing

/// The three prohibitions of `SecurityKit`, asserted structurally rather than
/// trusted as convention (m4-security threat matrix).
///
/// Two of the target's three threat-matrix rows are *applicable by prohibition*:
/// there is no subprocess to sandbox and no write to audit, because neither
/// exists. A prohibition that is only written down is a comment; these tests are
/// what make it a fact, and what make its violation a failing suite rather than a
/// code review someone was too busy to do.
///
/// **Every scan here is anchored positively first.** A structural guard that
/// reads nothing passes trivially and proves nothing — the M3-0 task 8.1 lesson.
/// So each test asserts the scan actually read source, and that a token which
/// *is* present was found, before asserting anything is absent.
@Suite("Security egress and prohibition structure")
struct EgressStructureTests {
    // MARK: - Threat matrix: subprocess / process integration (by prohibition)

    /// `SecurityKit` spawns nothing. Security.framework and `getxattr` replace
    /// `spctl`, `codesign` and the `xattr` command-line tool, so no advisory scan
    /// and no artifact inspection ever reaches a process boundary.
    @Test("The security target spawns no process and names no command-line tool")
    func securityKitSpawnsNothing() throws {
        let sources = try SecurityKitSources.load()
        SecurityKitSources.assertAnchored(sources)

        for token in ["Process", "posix_spawn", "NSTask", "spctl", "codesign", "xattr"] {
            let offenders = sources.filter { $0.code.containsIdentifier(token) }
            #expect(
                offenders.isEmpty,
                "a subprocess token (\(token)) leaked into \(offenders.map(\.name).sorted())"
            )
        }

        // A literal tool path is a substring, not an identifier.
        for path in ["/usr/bin/", "/bin/", "/usr/sbin/"] {
            let offenders = sources.filter { $0.code.contains(path) }
            #expect(
                offenders.isEmpty,
                "an executable path (\(path)) leaked into \(offenders.map(\.name).sorted())"
            )
        }
    }

    // MARK: - Threat matrix: filesystem write during classification (by prohibition)

    /// Inspection is read-only: no byte of an inspected artifact can change,
    /// because the target contains no call that could change one.
    ///
    /// Stated **exhaustively and positively** rather than as an allow-list, which
    /// is the same discipline the `local-package-metadata` guard uses: the set of
    /// files containing any write call must be a subset of the one file permitted
    /// to write at all — the advisory cache, whose single JSON file in
    /// `~/Library/Caches/` is derived, re-fetchable data and is not an artifact.
    /// A write appearing anywhere else fails the suite and forces a design
    /// conversation instead of passing quietly.
    @Test("The security target writes nothing outside its own advisory cache file")
    func securityKitWritesNothing() throws {
        let sources = try SecurityKitSources.load()
        SecurityKitSources.assertAnchored(sources)

        let writers = sources.filter { source in
            source.code.containsIdentifier("removexattr")
                || source.code.containsIdentifier("setxattr")
                || source.code.contains("removeItem")
                || source.code.contains("moveItem")
                || source.code.contains("createFile")
                || source.code.contains("write(to:")
        }

        #expect(
            Set(writers.map(\.name)).subtracting([SecurityKitSources.cacheFileName]).isEmpty,
            "a filesystem write leaked into \(writers.map(\.name).sorted())"
        )
    }

    // MARK: - Triangulation: the scanner itself

    /// The two tests above assert an **absence**, and an absence is exactly what
    /// a broken scanner reports for free. So the scanner is pointed at source
    /// that *does* violate each prohibition, and must find every one of them.
    ///
    /// Without this, `containsIdentifier` could return `false` unconditionally
    /// and the whole threat matrix would report green.
    @Test(
        "The prohibition scanner detects a violation of every token it guards",
        arguments: [
            "let task = Process()",
            "posix_spawn(&pid, path, nil, nil, argv, environ)",
            "let task = NSTask()",
            "spctl(assess: url)",
            "codesign(url)",
            "xattr(url)",
            "removexattr(path, name, 0)",
            "setxattr(path, name, value, size, 0, 0)"
        ]
    )
    func theScannerDetectsAViolation(violation: String) {
        let tokens = ["Process", "posix_spawn", "NSTask", "spctl", "codesign", "xattr",
                      "removexattr", "setxattr"]

        #expect(
            tokens.contains { violation.containsIdentifier($0) },
            "the scanner missed a real violation: \(violation)"
        )
    }

    /// The distinction the whole scan turns on. `xattr` the command-line tool is
    /// forbidden; `getxattr`/`listxattr` the C functions are the *mandated*
    /// read-only replacement for it. A substring scan would ban the mandated API
    /// and could then only be satisfied by deleting the feature — so the guard
    /// would be "passed" by removing the thing it exists to protect.
    @Test("The scanner separates the forbidden xattr tool from the mandated xattr C functions")
    func theScannerDistinguishesTheToolFromTheCFunctions() {
        let mandated = "let size = listxattr(path, names, capacity, 0)\n"
            + "let read = getxattr(path, name, buffer, capacity, 0, 0)"

        #expect(mandated.containsIdentifier("xattr") == false)
        #expect(mandated.containsIdentifier("getxattr"))
        #expect(mandated.containsIdentifier("listxattr"))
        // The same precision in the other direction.
        #expect("ProcessInfo.processInfo".containsIdentifier("Process") == false)
        #expect("let task = Process()".containsIdentifier("Process"))
    }

    /// Comment stripping is what lets the target *document* its prohibitions in
    /// the same directory the guard scans. `SecurityKit.swift` names `spctl`,
    /// `codesign` and `xattr` in prose; if stripping regressed, the guard would
    /// fail on its own documentation and the obvious "fix" would be to delete
    /// the documentation.
    @Test("Prose naming a forbidden token is stripped, while code using it is not")
    func commentsAreStrippedButCodeIsNot() throws {
        let sources = try SecurityKitSources.load()
        let namespace = try #require(sources.first { $0.name == "SecurityKit.swift" })

        #expect(namespace.code.containsIdentifier("codesign") == false)
        #expect(namespace.code.contains("advisoryCacheFileName"))
        #expect(namespace.code.contains("import Foundation"))
    }
}

// MARK: - The scan

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

    private static func stripComments(from source: String) -> String {
        var result = ""
        var characters = Array(source)
        var index = 0
        var inString = false
        var inBlockComment = false

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            if inBlockComment {
                if character == "*", next == "/" { inBlockComment = false; index += 2; continue }
                index += 1
                continue
            }
            if inString {
                if character == "\\" { index += 2; continue }
                if character == "\"" { inString = false }
                result.append(character)
                index += 1
                continue
            }
            if character == "\"" { inString = true; result.append(character); index += 1; continue }
            if character == "/", next == "*" { inBlockComment = true; index += 2; continue }
            if character == "/", next == "/" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
                continue
            }
            result.append(character)
            index += 1
        }
        return result
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
