import CryptoKit
import Foundation
import Testing

/// The fixtures are test *input*, so their integrity is a test concern.
///
/// Every advisory decode, every severity tier, every version-boundary case and
/// every matcher outcome in this target is computed from the files under
/// `Fixtures/`. That makes those files the most dangerous thing in the suite:
/// editing one is the easiest possible way to make a failing test pass while
/// looking like you fixed something.
///
/// `probe-manifest.txt` records the SHA-256 of every captured file, and these
/// tests recompute all of them on every run. A fixture cannot be edited, and a
/// fixture cannot be added or removed, without failing here first.
@Suite("Fixture manifest")
struct FixtureManifestTests {
    // MARK: - The digests

    @Test("Every fixture still hashes to the digest the manifest recorded")
    func everyFixtureMatchesItsRecordedDigest() throws {
        let manifest = try FixtureManifest.load()

        // The manifest must actually contain entries, or every check below
        // iterates zero times and reports success against nothing.
        #expect(manifest.entries.count >= 20, "the manifest parser found no entries")

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

    /// Both directions, because each one alone leaves a hole: listing a file
    /// that was deleted, and shipping a file nobody recorded.
    @Test("The manifest names every file in the tree, and every file it names exists")
    func theManifestNamesEveryFileInTheFixtureTree() throws {
        let manifest = try FixtureManifest.load()
        let onDisk = try FixtureManifest.filesOnDisk()

        #expect(onDisk.isEmpty == false, "the fixture tree walk found no files")

        let listed = Set(manifest.entries.map(\.path))
        #expect(listed.subtracting(onDisk).isEmpty, "the manifest names a file that is not there")
        #expect(onDisk.subtracting(listed).isEmpty, "a fixture is not named in the manifest")
    }

    /// The captures the other suites depend on are present by name, so a
    /// wholesale directory rename fails here with a clear reason rather than as
    /// a confusing decode error three phases later.
    @Test(
        "Each probe gate's capture is present",
        arguments: [
            "OSV/querybatch-request.json",
            "OSV/querybatch-response.json",
            "OSV/querybatch-affected-response.json",
            "OSV/vulns-RUSTSEC-2021-0139.json",
            "NVD/cveids-response.json",
            "NVD/ratelimited-response.body",
            "Versions/installed-versions.txt",
            "Versions/homebrew-pkg-version-spec-corpus.txt"
        ]
    )
    func eachProbeGateCaptureIsPresent(path: String) throws {
        let onDisk = try FixtureManifest.filesOnDisk()

        #expect(onDisk.contains(path), "a probe-gate capture is missing: \(path)")
    }

    // MARK: - The negative control

    /// The three tests above assert that nothing changed, and "nothing changed"
    /// is what a broken checker reports for free.
    ///
    /// So the checker is pointed at a *deliberately corrupted* copy of the real
    /// tree and must notice. One byte is flipped in a scratch copy — the real
    /// fixtures are never written to — and the digest comparison must reject it.
    /// Without this, `everyFixtureMatchesItsRecordedDigest` could be comparing
    /// two identical recomputations and passing forever.
    @Test("The digest check rejects a fixture whose bytes were edited")
    func theDigestCheckDetectsAnEditedFixture() throws {
        let manifest = try FixtureManifest.load()
        let entry = try #require(
            manifest.entries.first { $0.path == "Versions/installed-versions.txt" }
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
}

// MARK: - The manifest

/// One recorded fixture: its path relative to `Fixtures/`, and its SHA-256.
struct FixtureManifestEntry: Sendable, Hashable {
    let digest: String
    let path: String
}

/// Reads `Fixtures/probe-manifest.txt` and walks the fixture tree.
enum FixtureManifest {
    /// The fixtures as the tests actually consume them — the bundle copy, not
    /// the repository source. If `resources: [.copy("Fixtures")]` were dropped
    /// from the manifest, this would fail rather than silently reading a tree
    /// the built test bundle does not contain.
    static let root: URL = {
        guard let resourceURL = Bundle.module.resourceURL else {
            preconditionFailure("the SecurityKitTests bundle has no resource URL")
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

    /// Every file under `Fixtures/`, relative to it, excluding the manifest
    /// itself — a manifest cannot record its own digest.
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
