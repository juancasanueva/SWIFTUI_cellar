import CryptoKit
import Foundation
import Testing

/// The fixtures are test *input*, so their integrity is a test concern.
///
/// Every decode, every tag match, every rate-limit parse and every Markdown
/// degradation in this target is computed from the files under `Fixtures/`. That
/// makes those files the most dangerous thing in the suite: editing one is the
/// easiest possible way to make a failing test pass while looking like you fixed
/// something.
///
/// `probe-manifest.txt` records the SHA-256 of every captured file, and these
/// tests recompute all of them on every run.
@Suite("Release-notes fixture manifest")
struct ReleaseNotesFixtureManifestTests {
    // MARK: - The digests

    @Test("Every fixture still hashes to the digest the manifest recorded")
    func everyFixtureMatchesItsRecordedDigest() throws {
        let manifest = try FixtureManifest.load()

        // The manifest must actually contain entries, or every check below
        // iterates zero times and reports success against nothing.
        #expect(manifest.entries.count >= 17, "the manifest parser found no entries")

        for entry in manifest.entries {
            let url = FixtureManifest.root.appendingPathComponent(entry.path)
            let data = try Data(contentsOf: url)
            #expect(
                FixtureManifest.digest(of: data) == entry.digest,
                "\(entry.path) no longer matches its recorded digest"
            )
        }
    }

    // MARK: - The tree

    /// Both directions, because each one alone leaves a hole: listing a file that
    /// was deleted, and shipping a file nobody recorded.
    @Test("The manifest names every file in the tree, and every file it names exists")
    func theManifestNamesEveryFileInTheFixtureTree() throws {
        let manifest = try FixtureManifest.load()
        let onDisk = try FixtureManifest.filesOnDisk()

        #expect(onDisk.isEmpty == false, "the fixture tree walk found no files")

        let listed = Set(manifest.entries.map(\.path))
        #expect(listed.subtracting(onDisk).isEmpty, "the manifest names a file that is not there")
        #expect(onDisk.subtracting(listed).isEmpty, "a fixture is not named in the manifest")
    }

    /// Every stream the later phases consume is present by name, so a wholesale
    /// rename fails here with a clear reason rather than as a confusing decode
    /// error four phases later.
    @Test(
        "Each captured stream is present",
        arguments: [
            "GitHub/releases-git-populated.json",
            "GitHub/releases-empty.json",
            "GitHub/releases-no-matching-tag.json",
            "GitHub/releases-page-full.json",
            "GitHub/release-body-gfm.json",
            "GitHub/release-body-malformed.json",
            "GitHub/error-403-ratelimit.json",
            "GitHub/error-401-unauthorized.json",
            "GitHub/error-404-repo.json"
        ]
    )
    func eachCapturedStreamIsPresent(path: String) throws {
        let onDisk = try FixtureManifest.filesOnDisk()

        #expect(onDisk.contains(path), "a captured stream is missing: \(path)")
    }

    /// The addition this capability's fixture standard makes: **every body has a
    /// sibling `*.headers.txt`**.
    ///
    /// Asserted as a rule over the tree rather than as a list, so a body added
    /// later without its headers fails here rather than silently becoming the one
    /// capture whose rate-limit state nobody can read.
    @Test("Every captured body ships its verbatim response headers beside it")
    func everyCapturedBodyShipsItsHeaders() throws {
        let onDisk = try FixtureManifest.filesOnDisk()
        // The two authored body fixtures describe a *body*, not an exchange:
        // neither was captured from a response, so neither has response headers
        // to carry. Named rather than pattern-matched, so a third one cannot join
        // them by accident.
        let authoredBodies: Set<String> = [
            "GitHub/release-body-gfm.json",
            "GitHub/release-body-malformed.json"
        ]
        let bodies = onDisk.filter { $0.hasSuffix(".json") }.subtracting(authoredBodies)

        #expect(bodies.count >= 6, "the walk found no captured body to check")

        for body in bodies.sorted() {
            let headers = body.replacingOccurrences(of: ".json", with: ".headers.txt")
            #expect(onDisk.contains(headers), "\(body) ships without its captured headers")
        }
    }

    // MARK: - The negative control

    /// The tests above assert that nothing changed, and "nothing changed" is what
    /// a broken checker reports for free.
    ///
    /// So the checker is pointed at a *deliberately corrupted* copy of a real
    /// capture and must notice. One byte is flipped in a scratch copy — the real
    /// fixtures are never written to — and the digest comparison must reject it.
    @Test("The digest check rejects a fixture whose bytes were edited")
    func theDigestCheckDetectsAnEditedFixture() throws {
        let manifest = try FixtureManifest.load()
        let entry = try #require(
            manifest.entries.first { $0.path == "GitHub/releases-empty.json" }
        )
        let original = try Data(contentsOf: FixtureManifest.root.appendingPathComponent(entry.path))

        // The control: unedited bytes still match, so the assertion below is
        // about the edit and not about a broken digest function.
        #expect(FixtureManifest.digest(of: original) == entry.digest)

        var edited = original
        let index = try #require(edited.indices.last)
        edited[index] ^= 0xFF

        #expect(edited.count == original.count, "the edit changed length, not content")
        #expect(
            FixtureManifest.digest(of: edited) != entry.digest,
            "an edited fixture passed the digest check"
        )
    }

    // MARK: - The header reader

    /// `Fixture.headers` is a test helper that later phases assert *against*, so
    /// a bug in it would move a real failure into the wrong place.
    ///
    /// Anchored on the live 401 capture, whose most interesting property is an
    /// absence: a rejected credential carries **no** rate-limit header at all,
    /// which is exactly why "a rejected token is not a rate limit" is a captured
    /// fact rather than an assumption.
    @Test("The header reader parses a captured header block and drops the status line")
    func theHeaderReaderParsesACapturedBlock() throws {
        let unauthorized = try Fixture.headers("GitHub/error-401-unauthorized.headers.txt")

        #expect(unauthorized["content-type"] == "application/json; charset=utf-8")
        #expect(unauthorized["server"] == "github.com")
        #expect(unauthorized.keys.contains { $0.hasPrefix("HTTP/") } == false)
        #expect(
            unauthorized.keys.contains { $0.lowercased().hasPrefix("x-ratelimit") } == false,
            "the live 401 capture unexpectedly carries a rate-limit header"
        )

        // Triangulation: a 200 from the same host *does* carry them, so the
        // absence above is a property of the 401 and not of the reader.
        let populated = try Fixture.headers("GitHub/releases-git-populated.headers.txt")
        #expect(populated["x-ratelimit-limit"] == "60")
        #expect(populated["x-ratelimit-remaining"]?.isEmpty == false)
        #expect(populated["etag"]?.isEmpty == false)
    }
}

// MARK: - The manifest

/// One recorded fixture: its path relative to `Fixtures/`, and its SHA-256.
struct FixtureManifestEntry: Sendable, Hashable {
    let digest: String
    let path: String
}

/// Reads `Fixtures/probe-manifest.txt` and walks the fixture tree.
enum FixtureManifest {
    /// The fixtures as the tests actually consume them — the bundle copy, not the
    /// repository source. If `resources: [.copy("Fixtures")]` were dropped from
    /// the manifest, this would fail rather than silently reading a tree the built
    /// test bundle does not contain.
    static let root: URL = {
        guard let resourceURL = Bundle.module.resourceURL else {
            preconditionFailure("the ReleaseNotesTests bundle has no resource URL")
        }
        return resourceURL.appendingPathComponent("Fixtures")
    }()

    static let manifestName = "probe-manifest.txt"

    struct Contents: Sendable {
        let entries: [FixtureManifestEntry]
    }

    static func load() throws -> Contents {
        let text = try String(
            contentsOf: root.appendingPathComponent(manifestName),
            encoding: .utf8
        )
        let entries = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix("#") == false }
            .compactMap { line -> FixtureManifestEntry? in
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                guard fields.count == 2 else { return nil }
                return FixtureManifestEntry(digest: String(fields[0]), path: String(fields[1]))
            }
        return Contents(entries: entries)
    }

    /// Every file under `Fixtures/`, relative to it, excluding the manifest itself
    /// — a manifest cannot record its own digest.
    static func filesOnDisk() throws -> Set<String> {
        let manager = FileManager.default
        guard let walk = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }

        var found: Set<String> = []
        for case let url as URL in walk {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
            guard path != manifestName else { continue }
            found.insert(path)
        }
        return found
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
