import CryptoKit
import Foundation
import Testing

/// The doctor fixtures are test **input**, so their integrity is a test concern.
///
/// Every grammar row, the stream-split proof, the clean-run distinction and the
/// hostile-shape tolerance are computed from the files under `Fixtures/Doctor/`.
/// That makes those files the most dangerous thing in this suite: silently
/// re-saving one is the easiest possible way to make a failing test pass while
/// looking like a fix. `odd-grouping/stderr.txt` is the sharpest case — it is
/// invalid UTF-8 by construction, and an editor that helpfully "repairs" the
/// encoding on save would disarm the tolerance test without touching a line of
/// Swift.
///
/// The second thing this suite defends is **provenance**. One directory here was
/// captured from a real `brew doctor`; two were written by hand, because this
/// machine has real warnings and a clean run could not be produced on it (U10).
/// An unmarked hand-authored fixture is indistinguishable from a capture, so the
/// marker files are asserted **present** rather than trusted to stay there.
/// (`Fixtures/Bundle` standard, `SecurityKitTests/FixtureManifestTests` idiom.)
@Suite("Doctor fixture manifest")
struct DoctorFixtureManifestTests {

    @Test("Every doctor fixture still hashes to the digest the manifest recorded")
    func everyDoctorFixtureMatchesItsRecordedDigest() throws {
        let manifest = try DoctorFixtureManifest.load()

        // Without this, an unparsed manifest iterates zero times and reports
        // success against nothing at all.
        #expect(manifest.digests.count == 8, "the manifest parser found \(manifest.digests.count) digests")

        for (name, recorded) in manifest.digests.sorted(by: { $0.key < $1.key }) {
            let data = try DoctorFixtureManifest.data(at: name)
            #expect(
                DoctorFixtureManifest.digest(of: data) == recorded,
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
        let manifest = try DoctorFixtureManifest.load()
        let onDisk = try DoctorFixtureManifest.filesOnDisk()

        #expect(onDisk.isEmpty == false, "the fixture tree walk found no files")

        let listed = Set(manifest.digests.keys)
        #expect(listed.subtracting(onDisk).isEmpty, "the manifest names a file that is not there")
        #expect(onDisk.subtracting(listed).isEmpty, "a fixture is not named in the manifest")
    }

    /// Loading is through `Bundle.module`, which is how every other suite in this
    /// target reaches a fixture. If `resources: [.copy("Fixtures")]` were ever
    /// dropped from `Package.swift`, this fails rather than silently reading a
    /// repository tree the built test bundle does not contain.
    @Test(
        "Each named stream loads from the test bundle",
        arguments: [
            "warnings-run/stdout.txt",
            "warnings-run/stderr.txt",
            "clean-run/stdout.txt",
            "clean-run/stderr.txt",
            "odd-grouping/stdout.txt",
            "odd-grouping/stderr.txt"
        ]
    )
    func eachNamedStreamLoadsFromTheTestBundle(name: String) throws {
        let data = try DoctorFixtureManifest.data(at: name)
        // Zero bytes is a legitimate recorded value for two of these, so the
        // assertion is against the manifest rather than against non-emptiness.
        let manifest = try DoctorFixtureManifest.load()
        #expect(DoctorFixtureManifest.digest(of: data) == manifest.digests[name])
    }

    // MARK: - Provenance

    /// The capture record, read off the manifest rather than off the prose: this
    /// run exited **1** and put its whole document on **stderr**, leaving stdout
    /// one byte. Both facts are why `DoctorSource` and `DoctorParser` are shaped
    /// the way they are, so both are pinned here.
    @Test("The capture record pins the exit code, the argv and the stream split")
    func theCaptureRecordPinsTheExitCodeTheArgvAndTheStreamSplit() throws {
        let manifest = try DoctorFixtureManifest.load()

        #expect(manifest.values["brew-version"] == "6.0.15-125-g7372067")
        #expect(manifest.values["argv[1]"] == "doctor")
        #expect(manifest.values["argv[1]-exit"] == "1")
        #expect(manifest.values["environment"] == "HOMEBREW_NO_AUTO_UPDATE=1")

        // The split itself, read off the bytes rather than off the prose.
        let stdout = try DoctorFixtureManifest.data(at: "warnings-run/stdout.txt")
        let stderr = try DoctorFixtureManifest.data(at: "warnings-run/stderr.txt")

        #expect(stdout == Data("\n".utf8), "stdout is no longer the single newline U10 measured")
        #expect(stderr.count == 622, "the captured report is \(stderr.count) bytes, not 622")
        let report = String(decoding: stderr, as: UTF8.self)
        #expect(report.contains("Warning: "), "the capture no longer carries a warning block")
        #expect(
            report.contains("just used to help the Homebrew maintainers"),
            "the preamble that motivates the doctor weight is gone from the capture"
        )
    }

    /// A hand-authored fixture that is not marked as one is a capture as far as
    /// any later reader can tell. The marker lives **inside** each directory, so
    /// it survives a copy of the directory alone, and it is asserted present
    /// rather than assumed.
    @Test(
        "Each hand-authored directory carries its own visible marker",
        arguments: ["clean-run", "odd-grouping"]
    )
    func eachHandAuthoredDirectoryCarriesItsOwnMarker(directory: String) throws {
        let manifest = try DoctorFixtureManifest.load()

        let declared = manifest.values["hand-authored-marker[\(directory)]"]
        #expect(declared == "\(directory)/HAND-AUTHORED.txt", "the manifest does not declare the marker")

        let marker = try #require(declared)
        let text = String(decoding: try DoctorFixtureManifest.data(at: marker), as: UTF8.self)
        #expect(text.contains("HAND-AUTHORED"), "the marker does not say it is hand-authored")
        #expect(text.contains("NOT CAPTURED"), "the marker does not deny being a capture")

        // And the README says the same thing, so the claim survives someone
        // reading only the directory or only the record.
        let readme = String(decoding: try DoctorFixtureManifest.data(at: "README.md"), as: UTF8.self)
        #expect(
            readme.contains("`\(directory)/HAND-AUTHORED.txt`"),
            "README.md does not name \(directory)'s marker"
        )
    }

    /// The captured directory must **not** claim to be hand-authored, or the
    /// marker assertion above would pass over a tree where everything is marked
    /// and the distinction means nothing.
    @Test("The captured directory carries no hand-authored marker")
    func theCapturedDirectoryCarriesNoHandAuthoredMarker() throws {
        let manifest = try DoctorFixtureManifest.load()
        let onDisk = try DoctorFixtureManifest.filesOnDisk()

        #expect(manifest.values["captured-directories"] == "warnings-run")
        #expect(
            onDisk.contains("warnings-run/HAND-AUTHORED.txt") == false,
            "the captured directory is marked hand-authored"
        )
        #expect(manifest.values["hand-authored-marker[warnings-run]"] == nil)

        // The provenance lines agree with the markers, in both directions.
        #expect(manifest.values["provenance[warnings-run/stderr.txt]"]?.hasPrefix("captured;") == true)
        #expect(manifest.values["provenance[clean-run/stdout.txt]"]?.hasPrefix("hand-authored;") == true)
        #expect(manifest.values["provenance[odd-grouping/stderr.txt]"]?.hasPrefix("hand-authored;") == true)
    }

    // MARK: - The negative control

    /// Every assertion above reports success when nothing changed, and "nothing
    /// changed" is exactly what a broken checker reports for free. This proves
    /// the checker can still fail.
    @Test("A changed byte is detected")
    func aChangedByteIsDetected() throws {
        var data = try DoctorFixtureManifest.data(at: "warnings-run/stderr.txt")
        let recorded = try #require(try DoctorFixtureManifest.load().digests["warnings-run/stderr.txt"])

        #expect(DoctorFixtureManifest.digest(of: data) == recorded)
        data[0] ^= 0x01
        #expect(
            DoctorFixtureManifest.digest(of: data) != recorded,
            "flipping a bit did not change the digest, so the checker proves nothing"
        )
    }
}
