import Catalog
import Foundation
import Testing

@testable import BrewClient

/// The structural guards behind the snooze rule, across both targets that
/// implement it.
///
/// Split from `SnoozeProjectionTests`, which keeps the behaviour, because in M4
/// the guard grew and the behaviour did not — which is exactly what the
/// `local-package-metadata` delta asks for. The prohibition widened from "no
/// version comparator in the rule" to "no security comparator reachable from
/// any file this capability owns", plus an exhaustive whole-directory statement
/// so the file list cannot quietly become an escape hatch.
///
/// Every scan here has a **positive anchor** and a **violation control**. A
/// source scan with neither is a test that passes loudest when it reads nothing
/// at all, which is the one failure mode a prohibition cannot afford.
@Suite("Snooze guards")
struct SnoozeGuardTests {
    /// Where the snooze *rule* lives. The comparator assertions and the equality
    /// anchor apply here, and here only.
    static let brewClientRuleSources = [
        "Packages/CellarCore/Sources/BrewClient/PackageMetadata.swift",
        "Packages/CellarCore/Sources/BrewClient/InstalledFilterMode.swift"
    ]

    /// The snooze callers that live **outside this package entirely**.
    ///
    /// M5 adds a surface that snoozes several packages in one user action, and it
    /// lives in the app target — outside `CellarCore` altogether. LPM5 answers the
    /// question that raises directly: the guard's scope is enumerated
    /// exhaustively rather than derived from a target boundary, so a new snooze
    /// caller must either be **named here** or record its snoozes only through a
    /// source already in scope.
    ///
    /// **Option chosen: named here.** The alternative — proving the surface writes
    /// only through `Sources/Persistence/MetadataStore.swift` — is a claim about
    /// what a file does *not* reach, and it would hold vacuously the day someone
    /// adds a second write path. Naming the file puts its real bytes under the
    /// same comparator and security scans as the rule itself, which is the
    /// stronger of the two and the one that fails rather than shrugs.
    static let appSnoozeCallerSources = [
        "cellar/Installed/BulkActionBar.swift"
    ]

    /// Every source this capability owns, across both targets **and the app**: the
    /// rule, the outdated projection, the snooze writes and reads, the snapshot
    /// publication, the `Snooze` model in both schema versions, and the bulk
    /// surface that records several snoozes at once.
    ///
    /// `Sources/Persistence/DismissalStore.swift` is deliberately absent — it
    /// implements a different capability, and M4's proposal approved that edge —
    /// and the whole-directory scan below is what stops the absence from being
    /// an allow-list escape.
    static let capabilitySources = brewClientRuleSources + [
        "Packages/CellarCore/Sources/Persistence/MetadataStore.swift",
        "Packages/CellarCore/Sources/Persistence/LocalStores.swift",
        "Packages/CellarCore/Sources/Persistence/SchemaV1.swift",
        "Packages/CellarCore/Sources/Persistence/SchemaV2.swift"
    ] + appSnoozeCallerSources

    /// An ordering, however it is spelled.
    static let comparatorTokens = [
        "compare(", ".numeric", "NumericSearch", "versionCompare", "isNewer",
        "isOlder", "precedes", "<=", ">="
    ]

    /// The security comparator, however it is reached.
    static let securityTokens = [
        "SecurityKit", "StrictSemVer", "FixVersionComparison", "HomebrewRevision"
    ]

    /// The **repository** root, not the package root.
    ///
    /// Re-rooted in M5 (LPM5). The reader used to stop at `Packages/CellarCore`,
    /// which meant it could not open `cellar/Installed/BulkActionBar.swift` at
    /// all — and a scan that cannot open a file does not fail, it reads an empty
    /// string and passes. The per-file anchor below is what turns that into a
    /// failure, and re-rooting here is what makes the anchor satisfiable.
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // BrewClientTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // CellarCore
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // the repository

    static let packageRoot = repositoryRoot
        .appendingPathComponent("Packages/CellarCore", isDirectory: true)

    // MARK: - LPM5 — no version comparator in the rule

    /// The structural half of the snooze rule: no ordering comparison of version
    /// strings was performed to reach those results, because no comparator
    /// exists in this capability at all.
    ///
    /// Unchanged in substance from its pre-M4 form — same tokens, same equality
    /// anchor, same two files. Only the file reader underneath it was
    /// generalized, so the guard could be extended to a second target without
    /// silently reading nothing.
    @Test("No version comparator exists anywhere in the snooze rule")
    func noVersionComparatorExists() throws {
        let source = try Self.brewClientRuleSources
            .map { Self.code(in: try Self.source(at: $0)) }
            .joined(separator: "\n")

        for comparator in Self.comparatorTokens {
            #expect(source.contains(comparator) == false, "a version comparator (\(comparator)) leaked in")
        }
        // The rule really is one equality.
        #expect(source.contains("snoozedVersion == candidate"))
    }

    /// The control. Without it, the scan above passes just as happily against a
    /// file it failed to open.
    @Test("The comparator scanner detects an ordering when there is one")
    func theComparatorScannerDetectsAnOrdering() {
        let violations = [
            "let ordered = candidate.compare(snoozedVersion, options: .numeric)",
            "if snoozedVersion >= candidate { return true }",
            "guard snoozedVersion.precedes(candidate) else { return false }",
            "func isNewer(_ lhs: String, _ rhs: String) -> Bool { lhs > rhs }"
        ]
        for violation in violations {
            #expect(
                Self.comparatorTokens.contains { Self.code(in: violation).contains($0) },
                "the scanner read straight past: \(violation)"
            )
        }
        // And it does not fire on the rule as written, or the scan above would
        // be unsatisfiable rather than satisfied.
        #expect(
            Self.comparatorTokens.contains {
                Self.code(in: "snoozedVersion == candidate").contains($0)
            } == false
        )
    }

    /// The scope follows every snooze caller, including one outside this package.
    ///
    /// LPM5's M5 clause, and the reason the reader was re-rooted: the enumerated
    /// scope is exhaustive rather than target-derived, so a bulk-snooze surface in
    /// the app target cannot satisfy the guarantee by simply not being on the
    /// list. It is on the list, and it is held to the **same** forbidden
    /// comparator tokens as the rule itself — a caller that constructed, compared
    /// or ordered a version string of its own would fail here rather than pass
    /// silently.
    @Test(
        "No snooze caller outside this package can evade the guard",
        arguments: SnoozeGuardTests.appSnoozeCallerSources
    )
    func noSnoozeCallerOutsideThisPackageCanEvadeTheGuard(path: String) throws {
        let source = Self.code(in: try Self.source(at: path))
        let anchor = (path as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")

        // The per-file anchor, kept from the scan above and load-bearing here for
        // a sharper reason: this reader had to be re-rooted to reach this file at
        // all, and a re-rooting that silently opened nothing would otherwise pass.
        #expect(source.isEmpty == false, "\(path) read as empty")
        #expect(source.contains(anchor), "\(path) never mentions \(anchor); the wrong file was read")
        // It really is a snooze caller, or the scope names a file that proves
        // nothing.
        #expect(source.contains("snooze") || source.contains("Snooze"))

        for comparator in Self.comparatorTokens {
            #expect(source.contains(comparator) == false, "\(path) reaches for a comparator (\(comparator))")
        }
        for token in Self.securityTokens {
            #expect(source.contains(token) == false, "\(path) references \(token)")
        }
    }

    // MARK: - The security comparator is structurally unreachable

    /// Six files, two targets, one prohibition.
    ///
    /// This capability spans `BrewClient` (the rule) and `Persistence` (the
    /// storage), and M4 gives `Persistence` a `SecurityKit` edge for an
    /// unrelated model. The prohibition is therefore **file-scoped, not
    /// target-scoped**: a target-wide reading would forbid an edge the proposal
    /// already approved, and would have to be relaxed the moment it was written
    /// — which is how a guard becomes decoration.
    ///
    /// Each file is anchored on its own name, so a scan that opened nothing, or
    /// opened the wrong file, fails instead of passing for free.
    @Test(
        "No security comparator is reachable from snooze",
        arguments: SnoozeGuardTests.capabilitySources
    )
    func noSecurityComparatorIsReachableFromSnooze(path: String) throws {
        let source = Self.code(in: try Self.source(at: path))
        let anchor = (path as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")

        #expect(source.isEmpty == false, "\(path) read as empty")
        #expect(source.contains(anchor), "\(path) never mentions \(anchor); the wrong file was read")

        for token in Self.securityTokens {
            #expect(source.contains(token) == false, "\(path) references \(token)")
        }
    }

    @Test("The security scanner detects a reference when there is one")
    func theSecurityScannerDetectsAReference() {
        let violations = [
            "import SecurityKit",
            "let parsed = StrictSemVer.parse(snoozedVersion)",
            "let verdict = FixVersionComparison.stillAffected",
            "let (upstream, _) = HomebrewRevision.split(candidate)"
        ]
        for violation in violations {
            #expect(
                Self.securityTokens.contains { Self.code(in: violation).contains($0) },
                "the scanner read straight past: \(violation)"
            )
        }
        #expect(
            Self.securityTokens.contains {
                Self.code(in: "snoozedVersion == candidate").contains($0)
            } == false
        )
    }

    /// Stated exhaustively over the whole directory, not as an allow-list.
    ///
    /// The six-file list above names the files this capability owns, and a list
    /// is an escape hatch: a seventh `Persistence` file importing `SecurityKit`
    /// would satisfy every assertion above by simply not being on it. Scanning
    /// the directory turns that into a failing test and a design conversation.
    @Test("DismissalStore is the only Persistence file importing SecurityKit")
    func dismissalStoreIsTheOnlyPersistenceFileImportingSecurityKit() throws {
        let directory = Self.packageRoot.appendingPathComponent("Sources/Persistence", isDirectory: true)
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map(\.lastPathComponent)
            .sorted()

        // The enumeration really walked a directory of real sources.
        #expect(files.count >= 8, "the Persistence scan found only \(files)")
        #expect(files.contains("DismissalStore.swift"))
        #expect(files.contains("SchemaV2.swift"))

        var importers: [String] = []
        for file in files where Self.importsSecurityKit(
            try Self.source(at: "Packages/CellarCore/Sources/Persistence/\(file)")
        ) {
            importers.append(file)
        }

        #expect(importers == ["DismissalStore.swift"], "SecurityKit is imported by \(importers)")
    }

    @Test("The import scanner tells an import from a mention and from an absence")
    func theImportScannerDetectsASecondImport() {
        #expect(Self.importsSecurityKit("import Foundation\nimport SecurityKit\n"))
        #expect(Self.importsSecurityKit("import SwiftData\n") == false)
        // A comment is not an import: comments are stripped first, which is what
        // lets a doc comment explain the rule without breaking it.
        #expect(
            Self.importsSecurityKit("// This file deliberately avoids import SecurityKit\n") == false
        )
    }

    // MARK: - Behaviour identical, guard grown

    /// The "identical" half of the delta.
    ///
    /// The five behavioural tests are *named* rather than re-asserted — they
    /// live next door and re-running them here would be noise. What is checked
    /// is that they are still present, because the failure mode this guard
    /// exists to prevent is a prohibition that grows while the behaviour it
    /// protects is quietly deleted in the same commit.
    @Test("Snooze behaviour is byte-identical to its pre-comparator form")
    func snoozeBehaviourIsByteIdenticalToItsPreComparatorForm() throws {
        let behaviour = try Self.source(at: "Packages/CellarCore/Tests/BrewClientTests/SnoozeProjectionTests.swift")
        for name in [
            "theBadgeIsSuppressedWhileUnchanged",
            "aNewerOfferedVersionRevivesTheBadge",
            "anyDifferentOfferedVersionRevivesTheBadge",
            "unsnoozingRestoresTheBadgeImmediately",
            "aSnoozedPackageIsStillListed"
        ] {
            #expect(behaviour.contains("func \(name)("), "the behavioural test \(name) is gone")
        }

        // And the rule is still the one equality, over the matrix those five
        // cover: suppression only on an exact match, revival on everything else.
        #expect(PackageMetadata.isSnoozed(offering: "1.2.3", snoozedVersion: "1.2.3"))
        for offered in ["1.3.0", "1.2.3_1", "1.2.2", "1.2.3-1", "1.2", "1.2.30"] {
            #expect(PackageMetadata.isSnoozed(offering: offered, snoozedVersion: "1.2.3") == false)
        }

        // No entry point grew a scheme, an ordering or a comparator to consult.
        let rule = Self.code(in: try Self.source(at: "Packages/CellarCore/Sources/BrewClient/PackageMetadata.swift"))
        for widening in ["scheme", "Comparator", "sorted", "SemVer"] {
            #expect(rule.contains(widening) == false, "the snooze rule grew \(widening)")
        }
    }

    // MARK: -

    /// Whether a source *declares* the import, as opposed to naming the module
    /// in prose.
    static func importsSecurityKit(_ source: String) -> Bool {
        code(in: source)
            .split(separator: "\n")
            .contains { $0.trimmingCharacters(in: .whitespaces) == "import SecurityKit" }
    }

    static func code(in source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let marker = line.range(of: "//") else { return line }
                return line[line.startIndex..<marker.lowerBound]
            }
            .joined(separator: "\n")
    }

    /// Reads any file in the **repository** by its repository-root-relative path.
    ///
    /// Generalized twice, for the same reason each time. First from a
    /// `Sources/BrewClient/`-only reader, because this capability spans two
    /// package targets; then from a package-rooted reader, because M5 adds a
    /// snooze caller in the app target that lives outside the package entirely. A
    /// guard that could only read part of its own scope would have to be extended
    /// by pointing it at files it silently could not open — and a scan that reads
    /// nothing passes.
    static func source(at path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }
}
