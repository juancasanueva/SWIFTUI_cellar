import Catalog
import Foundation
import ReleaseNotes
import Testing

/// The prohibitions of `ReleaseNotes`, asserted structurally rather than trusted
/// as convention.
///
/// Three of this capability's rules are *absences*, and an absence cannot be
/// tested behaviourally: the failure would be a call nobody makes. There is one
/// `URLSession` in the target; the entry point that uses it requires a grant;
/// there is no plural shape anywhere. A prohibition that is only written down is a
/// comment — these tests are what make its violation a failing suite rather than
/// a code review someone was too busy to do.
///
/// **Every scan is anchored positively first.** A structural guard that reads
/// nothing passes trivially and proves nothing (the M3-0 task 8.1 lesson, already
/// paid for once in this project).
@Suite("Release-notes egress and prohibition structure")
struct ReleaseNotesEgressStructureTests {
    // MARK: - One URLSession, in one file

    @Test("URLSession and URLRequest appear in exactly one file")
    func urlSessionAppearsInExactlyOneFile() throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        for token in ["URLSession", "URLRequest", "URLSessionConfiguration"] {
            let owners = sources.filter { $0.code.containsIdentifier(token) }.map(\.name)
            #expect(
                Set(owners) == [ReleaseNotesSources.sourceFileName],
                "\(token) appears in \(owners.sorted()), not only in \(ReleaseNotesSources.sourceFileName)"
            )
        }
    }

    /// The scanner, pointed at the file it names, so the equality above is not the
    /// equality of a scanner that finds nothing anywhere.
    @Test("The one permitted file really does contain the session")
    func theOnePermittedFileReallyContainsTheSession() throws {
        let sources = try ReleaseNotesSources.load()
        let owner = try #require(
            sources.first { $0.name == ReleaseNotesSources.sourceFileName },
            "the target has no \(ReleaseNotesSources.sourceFileName)"
        )

        #expect(owner.code.containsIdentifier("URLSession"))
        #expect(owner.code.containsIdentifier("URLRequest"))
    }

    // MARK: - The fetch entry point requires a grant

    /// The compile-time gate, asserted as source because its violation would not
    /// compile and therefore cannot be caught at runtime.
    @Test("Every declaration that can reach the network takes a ReleaseNotesGrant")
    func everyNetworkDeclarationTakesAGrant() throws {
        let sources = try ReleaseNotesSources.load()
        let owner = try #require(
            sources.first { $0.name == ReleaseNotesSources.sourceFileName }
        )

        // The protocol requirement and the shipped conformance both take one.
        let signatures = owner.code.components(separatedBy: "func releases(")
        #expect(signatures.count >= 3, "the fetch surface has \(signatures.count - 1) declarations")
        for signature in signatures.dropFirst() {
            let head = String(signature.prefix(400))
            #expect(
                head.contains("grant: ReleaseNotesGrant"),
                "a fetch declaration takes no grant: \(head.prefix(160))"
            )
        }
    }

    /// The other half: the grant is unforgeable, so requiring one is a real gate
    /// and not a parameter anybody can synthesise.
    @Test("The grant cannot be constructed from outside the module")
    func theGrantCannotBeConstructedFromOutsideTheModule() throws {
        let sources = try ReleaseNotesSources.load()
        let declaring = try #require(
            sources.first { $0.code.contains("public struct ReleaseNotesGrant") }
        )

        #expect(declaring.code.contains("init()"))
        #expect(declaring.code.contains("public init()") == false)
    }

    // MARK: - No shape that could fan out

    /// A plural entry point is all it would take for a list render or a bulk
    /// operation to become thirty requests. The surest guard is for the shape not
    /// to exist, and this is what asserts it does not.
    @Test(
        "The target contains no plural, bulk or prefetch shape",
        arguments: ["[PackageID]", "submitBulk", "prefetch", "loadAll", "releasesForAll"]
    )
    func theTargetContainsNoPluralShape(token: String) throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        let offenders = sources.filter { $0.code.contains(token) }

        #expect(
            offenders.isEmpty,
            "\(token) appears in \(offenders.map(\.name).sorted())"
        )
    }

    /// And no ambient trigger. A `.task` modifier, a `Timer` or a notification
    /// observer would each start work nobody clicked.
    @Test(
        "The target names no ambient trigger",
        arguments: ["Timer", "NotificationCenter", "DispatchSourceTimer", "URLSessionTaskDelegate"]
    )
    func theTargetNamesNoAmbientTrigger(token: String) throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        let offenders = sources.filter { $0.code.containsIdentifier(token) }

        #expect(offenders.isEmpty, "\(token) appears in \(offenders.map(\.name).sorted())")
    }

    // MARK: - One host, compiled in

    /// An exact **set equality**, not an allow-list: a second `https://` literal
    /// anywhere in the target fails the suite, whatever it is for.
    ///
    /// The interpolation half is the other door. `"https://\(host)/v1"` is one
    /// literal and would pass a set comparison while building its host from a
    /// value, so no URL literal here may contain `\(`.
    @Test("Exactly one constant host appears in the target, and it does not interpolate")
    func exactlyOneConstantHostAppearsInTheTarget() throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        let literals = sources.flatMap { ReleaseNotesSources.stringLiterals(in: $0.code) }
        let urls = literals.filter { $0.contains("https://") }

        #expect(
            Set(urls) == [GitHubReleaseNotesSource.baseURL],
            "the target's URL literals are \(Set(urls).sorted())"
        )
        // The declared constant is a real host rather than an empty string that
        // would make the equality above trivially satisfiable.
        #expect(GitHubReleaseNotesSource.baseURL == "https://api.github.com/")

        for url in urls {
            #expect(url.contains("\\(") == false, "a URL literal interpolates: \(url)")
        }
    }

    /// The literal scanner, pointed at source that *does* violate the rule.
    ///
    /// Without this, `stringLiterals(in:)` could return nothing at all and the
    /// exact-set assertion would fail loudly — but a scanner that returned only
    /// the known constant and dropped everything else would pass silently, which
    /// is the dangerous direction.
    @Test("The literal scanner finds a second host and an interpolated one")
    func theLiteralScannerFindsASecondHostAndAnInterpolatedOne() {
        let offending = """
            let leak = "https://evil.example.com/collect"
            let built = "https://\\(host)/repos"
            // "https://commented-out.example.com" is prose, not code
            """
        let found = ReleaseNotesSources
            .stringLiterals(in: ReleaseNotesSources.stripComments(from: offending))
            .filter { $0.contains("https://") }

        #expect(found.contains("https://evil.example.com/collect"))
        #expect(found.contains { $0.contains("\\(") })
        // Two, not three: the commented-out host is prose. That is the same
        // stripping the real scan depends on, exercised in the one direction
        // where getting it wrong passes quietly.
        #expect(found.count == 2, "the scanner read \(found)")
    }

    // MARK: - No process, no brew

    /// The whole flow spawns no process, and it cannot: `ReleaseNotes` depends on
    /// `Catalog` alone, so `BrewProcess` is not in its module graph. The scan is
    /// the belt; the build graph is the braces.
    @Test(
        "The target names no process, subprocess or command-line tool",
        arguments: ["Process", "posix_spawn", "NSTask", "BrewProcess", "BrewRunner", "SystemProcess"]
    )
    func theTargetNamesNoProcess(token: String) throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        let offenders = sources.filter { $0.code.containsIdentifier(token) }

        #expect(offenders.isEmpty, "\(token) leaked into \(offenders.map(\.name).sorted())")
    }

    @Test("The target names no executable path and no brew binary")
    func theTargetNamesNoExecutablePath() throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        for path in ["/usr/bin/", "/bin/", "/usr/sbin/", "/opt/homebrew/bin/brew"] {
            let offenders = sources.filter { $0.code.contains(path) }
            #expect(
                offenders.isEmpty,
                "an executable path (\(path)) leaked into \(offenders.map(\.name).sorted())"
            )
        }
    }

    /// The scanner, pointed at real violations, so every absence above is the
    /// absence of a violation rather than the absence of a scan.
    @Test(
        "The prohibition scanner detects a violation of every token it guards",
        arguments: [
            "let task = Process()",
            "posix_spawn(&pid, path, nil, nil, argv, environ)",
            "let task = NSTask()",
            "let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in }",
            "NotificationCenter.default.addObserver(self, selector: #selector(x), name: nil, object: nil)"
        ]
    )
    func theScannerDetectsAViolation(violation: String) {
        let tokens = ["Process", "posix_spawn", "NSTask", "Timer", "NotificationCenter"]

        #expect(
            tokens.contains { violation.containsIdentifier($0) },
            "the scanner missed a real violation: \(violation)"
        )
    }

    // MARK: - One writer

    /// The cache file is the only thing this target may write, because it is
    /// derived, re-fetchable data rather than anything the user owns.
    @Test("The target writes nothing outside its own cache file")
    func theTargetWritesNothingOutsideItsOwnCacheFile() throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        let writers = sources.filter { source in
            source.code.contains("removeItem")
                || source.code.contains("moveItem")
                || source.code.contains("createFile")
                || source.code.contains("write(to:")
                || source.code.contains("createDirectory")
        }

        #expect(
            Set(writers.map(\.name)).subtracting([ReleaseNotesSources.cacheFileName]).isEmpty,
            "a filesystem write leaked into \(writers.map(\.name).sorted())"
        )
        // Anchored: the permitted file really does write, so the subtraction
        // above is not empty because nothing writes anywhere.
        #expect(writers.map(\.name).contains(ReleaseNotesSources.cacheFileName))
    }

    // MARK: - The catalog is frozen

    /// `CatalogPackage`'s stored-property set, asserted exhaustively.
    ///
    /// This slice adds no field and spends none of slice 1's footprint headroom,
    /// and the way to keep that true is to write the set down: a field added
    /// here — by this capability or by anything else — fails this test before it
    /// reaches a snapshot on a user's disk.
    @Test("CatalogPackage's stored-property set is unchanged")
    func catalogPackagesStoredPropertySetIsUnchanged() throws {
        let package = CatalogPackageArrangement.formula(
            homepage: "https://github.com/acme/foo",
            stableURL: "https://github.com/acme/foo/archive/refs/tags/v1.tar.gz"
        )

        // A `Mirror`, not the encoded shape: an optional that happens to be `nil`
        // encodes to nothing, so a JSON-key comparison would silently stop
        // guarding whichever fields the arrangement left absent.
        let stored = Set(Mirror(reflecting: package).children.compactMap(\.label))

        #expect(
            stored == [
                "kind", "name", "displayName", "desc", "homepage", "license", "version",
                "tap", "dependencies", "buildDependencies", "dependents", "caveats",
                "deprecated", "deprecationReason", "deprecationDate", "disabled",
                "disableReason", "disableDate", "autoUpdates", "installCount365d",
                "caskInspection", "formulaSources"
            ],
            "CatalogPackage's stored-property set is \(stored.sorted())"
        )
        #expect(stored.count == 22)
        // Anchored: the mirror really did read a populated value, so the equality
        // above is not the equality of an empty set.
        #expect(package.formulaSources?.stableURL?.isEmpty == false)
    }

    @Test("The catalog schema version has not moved")
    func theCatalogSchemaVersionHasNotMoved() {
        #expect(CatalogSnapshot.currentSchemaVersion == 2)
        // And this capability's own version is independent of it, which is the
        // whole reason there are two.
        #expect(ReleaseNotesSchema.currentVersion == 1)
        #expect(ReleaseNotesSchema.currentVersion != CatalogSnapshot.currentSchemaVersion)
    }

    /// The whole flow, end to end, with **every** external effect counted.
    ///
    /// The design asks for a recording process seam here. There is none to inject
    /// and that is the point: `ReleaseNotes` depends on `Catalog` alone, so
    /// `BrewProcess` is not in its module graph and there is no process API to
    /// record. So the runtime half is stated the other way round — the complete
    /// set of external effects the flow produces is enumerated, and it contains
    /// one HTTP request and this capability's own cache file and nothing else.
    /// A spawned process would have to arrive through an effect this list does not
    /// contain. (Recorded amendment; see `design.md` → Apply-Time Amendments.)
    @Test("Resolve, fetch, match, cache and read back produce exactly two kinds of effect")
    @MainActor
    func theWholeFlowProducesExactlyTwoKindsOfEffect() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-release-notes-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("release-notes-v1.json")

        let network = RecordingNetwork(queue: [
            .releases(try Fixture.data("GitHub/releases-git-populated.json"), etag: "\"e\"")
        ])
        let files = RecordingFileAccess()

        let store = ReleaseNotesStore(
            source: GitHubReleaseNotesSource(session: network.session),
            cache: ReleaseNotesCache(fileURL: cacheURL, access: files),
            consent: FixedReleaseNotesConsent(.granted(at: Date(timeIntervalSince1970: 1))),
            credentials: nil,
            now: { Date(timeIntervalSince1970: 1_786_000_000) }
        )
        let id = PackageID(kind: .formula, name: "hyperfine")
        let candidates = RepositoryCandidates(
            homepage: "https://github.com/sharkdp/hyperfine",
            headURL: nil, stableURL: nil, caskDownloadURL: nil
        )

        // Resolve, fetch, match, cache.
        store.load(id, version: "1.18.0", candidates: candidates)
        await store.waitForLoad(id)
        // Read back.
        store.load(id, version: "1.18.0", candidates: candidates)
        await store.waitForLoad(id)

        #expect(store.state(for: id).outcome?.release?.tagName == "v1.18.0")

        // Effect one: exactly one HTTP request, to the one compiled-in host.
        //
        // Counted through this test's **own** tagged recorder. A process-global
        // counter stood beside this one and was removed: it could be reset by a
        // concurrently-starting sibling suite, which makes an egress guard able
        // to report a false zero — the one failure mode a guard must not have.
        // That no *other* session exists to reach is a structural claim, proved
        // above by `urlSessionAppearsInExactlyOneFile`, not a runtime one.
        #expect(network.requestCount == 1, "the flow issued \(network.requestCount) requests")
        #expect(network.exchanges.allSatisfy { $0.url.host() == "api.github.com" })

        // Effect two: this capability's own file, and no other path at all.
        let touched = await files.allPaths
        #expect(touched.isEmpty == false, "the recorder saw nothing, so it proves nothing")
        #expect(
            Set(touched) == [cacheURL.path],
            "the flow touched \(Set(touched).subtracting([cacheURL.path]).sorted())"
        )
        #expect(await files.writes.count == 1, "the flow wrote more than once")

        // And nothing else appeared in the directory beside the cache file — a
        // lock file, a temporary spool or a spawned tool's output would show up
        // here.
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents == ["release-notes-v1.json"], "the flow left \(contents)")
    }

    /// The dependency claim itself: this target sees `Catalog` and nothing else
    /// from the package. Asserted over the imports a reviewer reads.
    @Test("The target imports only Foundation, Catalog, Observation and Security")
    func theTargetImportsOnlyItsDeclaredDependencies() throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        var imported: Set<String> = []
        for source in sources {
            for line in source.code.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                imported.insert(String(trimmed.dropFirst("import ".count)))
            }
        }

        #expect(imported.isEmpty == false, "the scan found no import at all")
        #expect(
            imported.subtracting(["Foundation", "Catalog", "Observation", "Security"]).isEmpty,
            "the target imports \(imported.sorted())"
        )
        // Anchored: it really does import the one package dependency it declares.
        #expect(imported.contains("Catalog"))
    }
}
