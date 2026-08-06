import Foundation
import SecurityKit
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

    // MARK: - Threat matrix: network egress

    /// Advisory acquisition reaches exactly two hosts, and both are compiled in.
    ///
    /// Stated as an **exact set equality**, not as an allow-list: a third
    /// `https://` literal anywhere in the target fails the suite, whatever it is
    /// for. That is only affordable because provenance in `EcosystemMapping`
    /// records `host/owner/repo` without a scheme (batch 2, deviation 16) — a
    /// string that is not a URL cannot become a request by accident, so the
    /// guard never has to distinguish a URL that is requested from a URL that is
    /// merely cited.
    ///
    /// The interpolation half is the other door. `"https://\(host)/v1"` is one
    /// literal and would pass a set comparison while building its host from a
    /// value; no URL literal in this target may contain `\(`.
    @Test("Exactly two constant hosts appear in the target, and neither interpolates")
    func onlyTwoConstantHostsAppearInTheTarget() throws {
        let sources = try SecurityKitSources.load()
        SecurityKitSources.assertAnchored(sources)

        let literals = sources.flatMap { SecurityKitSources.stringLiterals(in: $0.code) }
        let urls = literals.filter { $0.contains("https://") }

        #expect(
            Set(urls) == [OSVSource.baseURL, NVDSource.baseURL],
            "the target's URL literals are \(Set(urls).sorted())"
        )
        // The declared constants are real hosts rather than empty strings that
        // would make the equality above trivially satisfiable.
        #expect(OSVSource.baseURL == "https://api.osv.dev/")
        #expect(NVDSource.baseURL == "https://services.nvd.nist.gov/rest/json/")

        for url in urls {
            #expect(url.contains("\\(") == false, "a URL literal interpolates: \(url)")
        }
    }

    /// The literal scanner, pointed at source that *does* violate the rule.
    ///
    /// Without this, `stringLiterals(in:)` could return nothing at all and the
    /// exact-set assertion above would fail loudly — but a scanner that returned
    /// only the two known constants and dropped everything else would pass
    /// silently, which is the dangerous direction.
    @Test("The literal scanner finds a third host and an interpolated one")
    func theLiteralScannerFindsAThirdHostAndAnInterpolatedOne() {
        let offending = """
            let leak = "https://evil.example.com/collect"
            let built = "https://\\(host)/v1/querybatch"
            // "https://commented-out.example.com" is prose, not code
            """
        let found = SecurityKitSources
            .stringLiterals(in: SecurityKitSources.stripComments(from: offending))
            .filter { $0.contains("https://") }

        #expect(found.contains("https://evil.example.com/collect"))
        #expect(found.contains { $0.contains("\\(") })
        // Two, not three: the commented-out host is prose. That is the same
        // stripping the real scan depends on, exercised in the one direction
        // where getting it wrong passes quietly.
        #expect(found.count == 2, "the scanner read \(found)")
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
