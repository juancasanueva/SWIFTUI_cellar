import Foundation
import Testing

@testable import SecurityKit

/// What is in scope for signature and notarization assessment, and — mostly —
/// what is not.
///
/// A keg is dominated by headers, man pages, completion scripts and symlinks,
/// none of which carries a signature. The predicate's job is to say `nil`
/// quietly for all of them, so "only where a signed, assessable artifact exists"
/// is a bounded fact rather than an unbounded walk.
@Suite("Artifact assessability")
struct ArtifactAssessabilityTests {
    // MARK: - Bundles

    /// The four bundle extensions the design names, each built with a real
    /// `Contents/MacOS` executable inside a temporary tree.
    @Test(
        "A bundle with a Contents/MacOS executable is assessable",
        arguments: ["app", "framework", "xpc", "bundle"]
    )
    func aBundleWithAContentsMacOSExecutableIsAssessable(pathExtension: String) throws {
        try withTemporaryDirectory { root in
            let bundle = root.appendingPathComponent("Thing.\(pathExtension)")
            try Self.makeBundle(at: bundle)

            #expect(ArtifactAssessability.classify(bundle) == .bundle)
        }
    }

    /// The `Contents/MacOS` executable is the whole of what makes a directory a
    /// *code* bundle. A directory named `.app` with nothing runnable in it is a
    /// folder with a suffix, and the probe's `the-unarchiver` Caskroom leftover
    /// is exactly that shape in the wild.
    @Test("A bundle-shaped directory with no executable inside is not assessable")
    func aBundleShapedDirectoryWithNoExecutableIsNotAssessable() throws {
        try withTemporaryDirectory { root in
            let hollow = root.appendingPathComponent("Hollow.app")
            try FileManager.default.createDirectory(
                at: hollow.appendingPathComponent("Contents/Resources"),
                withIntermediateDirectories: true
            )

            #expect(ArtifactAssessability.classify(hollow) == nil)
        }
    }

    @Test("A directory that is not bundle-shaped is not assessable")
    func aPlainDirectoryIsNotAssessable() throws {
        try withTemporaryDirectory { root in
            let plain = root.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

            #expect(ArtifactAssessability.classify(plain) == nil)
        }
    }

    // MARK: - Mach-O regular files

    /// The four magics the design names, written **as they appear on disk**.
    ///
    /// This distinction is the whole test. `ripgrep-header-64.bin`, captured from
    /// a real brew-installed executable, begins `cf fa ed fe` — which is
    /// `0xfeedfacf` read as a little-endian `UInt32`. A predicate that compares
    /// the first four bytes to `0xfeedfacf` in the wrong byte order matches
    /// nothing at all on this machine.
    @Test(
        "A regular file whose first four bytes are Mach-O magic is assessable",
        arguments: [
            [0xce, 0xfa, 0xed, 0xfe],  // 0xfeedface, little-endian on disk
            [0xfe, 0xed, 0xfa, 0xce],  // 0xfeedface, big-endian on disk
            [0xcf, 0xfa, 0xed, 0xfe],  // 0xfeedfacf, little-endian on disk
            [0xfe, 0xed, 0xfa, 0xcf],  // 0xfeedfacf, big-endian on disk
            [0xca, 0xfe, 0xba, 0xbe],  // fat, big-endian
            [0xbe, 0xba, 0xfe, 0xca]   // 0xbebafeca, the swapped fat magic
        ] as [[UInt8]]
    )
    func aRegularFileWhoseFirstFourBytesAreMachOMagicIsAssessable(magic: [UInt8]) throws {
        try withTemporaryDirectory { root in
            let file = root.appendingPathComponent("binary")
            try Data(magic + Array(repeating: 0, count: 60)).write(to: file)

            #expect(ArtifactAssessability.classify(file) == .machO)
        }
    }

    /// The positive anchor over **real bytes**, not synthesised ones. Without it
    /// the parameterized test above proves only that the predicate agrees with
    /// the constants the same author typed into both sides.
    @Test("A real brew-installed executable's captured header is assessable")
    func aRealBrewInstalledExecutableHeaderIsAssessable() throws {
        let header = try Fixture.data("MachO/ripgrep-header-64.bin")
        #expect(Array(header.prefix(4)) == [0xcf, 0xfa, 0xed, 0xfe], "the capture changed shape")

        try withTemporaryDirectory { root in
            let file = root.appendingPathComponent("rg")
            try header.write(to: file)

            #expect(ArtifactAssessability.classify(file) == .machO)
        }
    }

    @Test("A file shorter than four bytes is not assessable and does not trap")
    func aFileShorterThanFourBytesIsNotAssessable() throws {
        try withTemporaryDirectory { root in
            for (name, bytes) in [("empty", [] as [UInt8]), ("three", [0xcf, 0xfa, 0xed])] {
                let file = root.appendingPathComponent(name)
                try Data(bytes).write(to: file)

                #expect(ArtifactAssessability.classify(file) == nil)
            }
        }
    }

    // MARK: - Symlinks

    /// A symlink to a Mach-O file is **not** assessable as a regular file.
    ///
    /// Following it would report the same binary once per link that points at
    /// it, and a keg's `bin/` is full of links into `libexec/`. Resolution is the
    /// locator's job, done once against the path Homebrew recorded — not the
    /// predicate's, done implicitly per candidate.
    @Test("A symlink is never assessable")
    func aSymlinkIsNeverAssessable() throws {
        try withTemporaryDirectory { root in
            let real = root.appendingPathComponent("real")
            try Data([0xcf, 0xfa, 0xed, 0xfe] + Array(repeating: 0, count: 60)).write(to: real)
            #expect(ArtifactAssessability.classify(real) == .machO, "the target must be assessable")

            let link = root.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

            #expect(ArtifactAssessability.classify(link) == nil)
        }
    }

    /// The cask case the probe measured: nine of ten Caskroom `.app` entries on
    /// this machine are symlinks into `/Applications`. The predicate refuses them
    /// too, which is precisely why `ArtifactLocator` must resolve the
    /// brew-recorded target before classifying rather than walking the Caskroom.
    @Test("A symlink to a bundle is refused, like every other symlink")
    func aSymlinkToABundleIsRefused() throws {
        try withTemporaryDirectory { root in
            let bundle = root.appendingPathComponent("Real.app")
            try Self.makeBundle(at: bundle)
            let link = root.appendingPathComponent("Linked.app")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle)

            #expect(ArtifactAssessability.classify(bundle) == .bundle)
            #expect(ArtifactAssessability.classify(link) == nil)
            #expect(
                ArtifactAssessability.classify(link.resolvingSymlinksInPath()) == .bundle,
                "resolving first is the supported route, and it must work"
            )
        }
    }

    // MARK: - Out of scope, silently

    @Test("A shell script, a man page and a header are all out of scope")
    func aShellScriptAManPageAndAHeaderAreAllOutOfScope() throws {
        try withTemporaryDirectory { root in
            let candidates: [(String, Data)] = [
                ("brew-wrapper.sh", try Fixture.data("MachO/shell-script.sh")),
                ("rg.1", try Fixture.data("MachO/manpage-header-64.txt")),
                ("ripgrep.h", Data("#ifndef RIPGREP_H\n#define RIPGREP_H\n#endif\n".utf8)),
                ("completion.zsh", Data("#compdef rg\n".utf8)),
                ("LICENSE", Data("MIT\n".utf8))
            ]

            for (name, bytes) in candidates {
                let file = root.appendingPathComponent(name)
                try bytes.write(to: file)

                #expect(
                    ArtifactAssessability.classify(file) == nil,
                    "\(name) reached the inspector"
                )
            }
        }
    }

    @Test("A missing path is not assessable")
    func aMissingPathIsNotAssessable() throws {
        try withTemporaryDirectory { root in
            #expect(ArtifactAssessability.classify(root.appendingPathComponent("absent")) == nil)
        }
    }

    // MARK: - The located artifact

    @Test("A location carries its package, its URL and its kind")
    func aLocationCarriesItsPackageURLAndKind() throws {
        try withTemporaryDirectory { root in
            let bundle = root.appendingPathComponent("Thing.app")
            try Self.makeBundle(at: bundle)

            let location = try #require(
                ArtifactLocation(packageID: .init(kind: .cask, name: "thing"), url: bundle)
            )
            #expect(location.kind == .bundle)
            #expect(location.url == bundle)
            #expect(location.packageID.name == "thing")
        }
    }

    /// The failable initialiser is the seam that makes "everything the engine
    /// sees was classified" true by construction rather than by convention.
    @Test("A location cannot be built for something the predicate rejects")
    func aLocationCannotBeBuiltForSomethingThePredicateRejects() throws {
        try withTemporaryDirectory { root in
            let script = root.appendingPathComponent("script.sh")
            try Data("#!/bin/sh\n".utf8).write(to: script)

            #expect(ArtifactLocation(packageID: .init(kind: .formula, name: "x"), url: script) == nil)
        }
    }

    // MARK: - Helpers

    private static func makeBundle(at url: URL) throws {
        let macOS = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data([0xcf, 0xfa, 0xed, 0xfe] + Array(repeating: 0, count: 60))
            .write(to: macOS.appendingPathComponent(url.deletingPathExtension().lastPathComponent))
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("assessability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
