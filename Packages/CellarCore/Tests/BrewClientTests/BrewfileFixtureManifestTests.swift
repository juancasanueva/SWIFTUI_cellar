import CryptoKit
import Foundation
import Testing

/// The Brewfile fixtures are test **input**, so their integrity is a test
/// concern.
///
/// Every grammar row, every skip reason, every stream-split assertion and the
/// U10 divergence check are computed from the files under `Fixtures/Bundle/`.
/// That makes those files the most dangerous thing in this suite: silently
/// re-saving one is the easiest possible way to make a failing test pass while
/// looking like a fix. `undecodable.brewfile` is the sharpest case — it is
/// invalid UTF-8 by construction, and an editor that helpfully "repairs" the
/// encoding on save would disarm the tolerance test without touching a line of
/// Swift.
///
/// `probe-manifest.txt` records a SHA-256 per stream and per file, and this
/// suite recomputes all of them on every run, in both directions: a fixture
/// cannot be edited, added or removed without failing here first.
/// (`Fixtures/Cleanup` standard, `SecurityKitTests/FixtureManifestTests` idiom.)
@Suite("Brewfile fixture manifest")
struct BrewfileFixtureManifestTests {

    @Test("Every Brewfile fixture still hashes to the digest the manifest recorded")
    func everyBrewfileFixtureMatchesItsRecordedDigest() throws {
        let manifest = try BrewfileFixtureManifest.load()

        // Without this, an unparsed manifest iterates zero times and reports
        // success against nothing at all.
        #expect(manifest.digests.count == 8, "the manifest parser found \(manifest.digests.count) digests")

        for (name, recorded) in manifest.digests.sorted(by: { $0.key < $1.key }) {
            let url = BrewfileFixtureManifest.root.appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            #expect(
                BrewfileFixtureManifest.digest(of: data) == recorded,
                "\(name) no longer matches its recorded digest"
            )
            #expect(
                data.count == manifest.byteCounts[name],
                "\(name) is \(data.count) bytes; the manifest recorded \(manifest.byteCounts[name] ?? -1)"
            )
        }
    }

    /// Both directions, because each one alone leaves a hole: naming a file that
    /// was deleted, and shipping a file nobody recorded.
    @Test("The manifest names every fixture in the tree, and every fixture it names exists")
    func theManifestNamesEveryFixtureInTheTree() throws {
        let manifest = try BrewfileFixtureManifest.load()
        let onDisk = try BrewfileFixtureManifest.filesOnDisk()

        #expect(onDisk.isEmpty == false, "the fixture tree walk found no files")

        let listed = Set(manifest.digests.keys)
        #expect(listed.subtracting(onDisk).isEmpty, "the manifest names a file that is not there")
        #expect(onDisk.subtracting(listed).isEmpty, "a fixture is not named in the manifest")
    }

    /// Loading is through `Bundle.module`, which is the way every other suite in
    /// this target reaches a fixture. If `resources: [.copy("Fixtures")]` were
    /// ever dropped from `Package.swift`, this fails rather than silently
    /// reading a repository tree the built test bundle does not contain.
    @Test(
        "Each named stream loads from the test bundle",
        arguments: [
            "dump-file.brewfile",
            "dump-stdout.txt",
            "dump-stderr.txt",
            "empty.brewfile",
            "hostile-ruby.brewfile",
            "mixed-kinds.brewfile",
            "trusted-taps.brewfile",
            "undecodable.brewfile"
        ]
    )
    func eachNamedStreamLoadsFromTheTestBundle(name: String) throws {
        let data = try Data(contentsOf: BrewfileFixtureManifest.root.appendingPathComponent(name))
        // Zero bytes is a legitimate recorded value for two of these, so the
        // assertion is against the manifest rather than against non-emptiness.
        let manifest = try BrewfileFixtureManifest.load()
        #expect(BrewfileFixtureManifest.digest(of: data) == manifest.digests[name])
    }

    // MARK: - The capture record

    /// The provenance the README and the manifest agree on: this dump exited
    /// `0` **and** wrote a non-empty stderr, and it wrote its document to the
    /// file rather than to stdout. Both facts are why `BundleDumpSource` is
    /// shaped the way it is, so both are pinned here rather than left as prose.
    @Test("The capture record pins the exit code, the argv and the stream split")
    func theCaptureRecordPinsTheExitCodeTheArgvAndTheStreamSplit() throws {
        let manifest = try BrewfileFixtureManifest.load()

        #expect(manifest.values["brew-version"] == "6.0.15-125-g7372067")
        #expect(
            manifest.values["argv[1]"]
                == "bundle dump --file <tmp>/Brewfile --force --formula --cask --tap"
        )
        #expect(manifest.values["argv[1]-exit"] == "0")

        // U8: `bundle check` evaluated the file. That is why `dump` is the only
        // subcommand this capability may ever construct.
        #expect(manifest.values["argv[2]"] == "bundle check --file <tmp>/Hostile.brewfile")
        #expect(manifest.values["argv[2]-exit"] == "1")
        let observation = try #require(manifest.values["argv[2]-observation"])
        #expect(observation.contains("EVALUATED"))
        #expect(observation.contains("marker.txt"))

        // The split itself, read off the bytes rather than off the prose.
        let root = BrewfileFixtureManifest.root
        let document = try Data(contentsOf: root.appendingPathComponent("dump-file.brewfile"))
        let stdout = try Data(contentsOf: root.appendingPathComponent("dump-stdout.txt"))
        let stderr = try String(
            contentsOf: root.appendingPathComponent("dump-stderr.txt"),
            encoding: .utf8
        )
        #expect(document.isEmpty == false, "the captured document is empty")
        #expect(stdout.isEmpty, "stdout was not empty, so the capture no longer shows the split")
        #expect(stderr.contains("circular dependency"), "the exit-0 warning is gone from the capture")
        #expect(
            String(decoding: document, as: UTF8.self).contains("circular dependency") == false,
            "a stderr diagnostic leaked into the captured document"
        )
    }

    // MARK: - The negative control

    /// Every assertion above reports success when nothing changed, and "nothing
    /// changed" is exactly what a broken checker reports for free. This proves
    /// the checker can still fail.
    @Test("A changed byte is detected")
    func aChangedByteIsDetected() throws {
        let url = BrewfileFixtureManifest.root.appendingPathComponent("mixed-kinds.brewfile")
        var data = try Data(contentsOf: url)
        let recorded = try #require(try BrewfileFixtureManifest.load().digests["mixed-kinds.brewfile"])

        #expect(BrewfileFixtureManifest.digest(of: data) == recorded)
        data[0] ^= 0x01
        #expect(
            BrewfileFixtureManifest.digest(of: data) != recorded,
            "flipping a bit did not change the digest, so the checker proves nothing"
        )
    }
}

/// `Fixtures/Bundle/`, read the way the tests consume it.
enum BrewfileFixtureManifest {
    static let root: URL = {
        guard let resourceURL = Bundle.module.resourceURL else {
            preconditionFailure("the BrewClientTests bundle has no resource URL")
        }
        return resourceURL.appendingPathComponent("Fixtures/Bundle")
    }()

    static let manifestName = "probe-manifest.txt"
    /// Not hashed by the manifest: a manifest cannot record its own digest, and
    /// the README changes whenever the prose does.
    static let unhashed: Set<String> = [manifestName, "README.md"]

    struct Contents: Sendable {
        /// `key=value` lines, verbatim.
        let values: [String: String]
        /// `sha256[name]=digest`.
        let digests: [String: String]
        /// `bytes[name]=count`.
        let byteCounts: [String: Int]
    }

    static func load() throws -> Contents {
        let text = try String(
            contentsOf: root.appendingPathComponent(manifestName),
            encoding: .utf8
        )

        var values: [String: String] = [:]
        var digests: [String: String] = [:]
        var byteCounts: [String: Int] = [:]

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator])
            let value = String(line[line.index(after: separator)...])
            values[key] = value

            if let name = bracketed(key, prefix: "sha256") {
                digests[name] = value
            } else if let name = bracketed(key, prefix: "bytes") {
                byteCounts[name] = Int(value)
            }
        }
        return Contents(values: values, digests: digests, byteCounts: byteCounts)
    }

    private static func bracketed(_ key: String, prefix: String) -> String? {
        guard key.hasPrefix(prefix + "["), key.hasSuffix("]") else { return nil }
        return String(key.dropFirst(prefix.count + 1).dropLast())
    }

    /// Every regular file under `Fixtures/Bundle/`, relative to it, excluding
    /// the files the manifest deliberately does not hash.
    static func filesOnDisk() throws -> Set<String> {
        let manager = FileManager.default
        guard let walk = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }

        var found: Set<String> = []
        for case let url as URL in walk {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
            guard unhashed.contains(path) == false else { continue }
            found.insert(path)
        }
        return found
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
