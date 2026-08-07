import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// Publication (`brewfile-management` BF9, design D2, DD4).
///
/// The bytes the user sees and the bytes that land on disk are the **dump's
/// bytes**: no reformatting, re-encoding, line-ending change, reordering,
/// filtering or appended provenance between acquisition and publication. The
/// write goes through the shipped `CatalogFileSystem` seam atomically, so a
/// failure leaves a pre-existing file exactly as it was.
///
/// The destination is chosen **per export**. Nothing is remembered: no
/// `UserDefaults` key, no `@AppStorage`, no security-scoped bookmark. A
/// remembered destination is an M6 Settings decision, and inventing one here
/// would be inventing a way to write to a path the user did not choose today.
@Suite("Brewfile publication")
struct BrewfilePublicationTests {

    static let destination = URL(fileURLWithPath: "/Users/someone/Documents/Brewfile")

    static func dumpDocument() throws -> Data {
        try Data(contentsOf: BrewfileFixtureManifest.root.appendingPathComponent("dump-file.brewfile"))
    }

    // MARK: - BF9 — the bytes are the dump's bytes

    @Test("Published bytes equal the dump's bytes, including the trailing newline")
    func publishedBytesEqualTheDumpsBytes() throws {
        let document = try Self.dumpDocument()
        let fileSystem = RecordingFileSystem()

        try BrewfilePublication.publish(document, to: Self.destination, using: fileSystem)

        let written = try #require(fileSystem.bytes(at: Self.destination))
        #expect(written == document, "the published bytes are not the document's bytes")
        #expect(written.last == UInt8(ascii: "\n"), "the trailing newline was lost")
        #expect(written.count == 5268)

        // Line for line, nothing added, removed, reordered or re-encoded.
        let before = String(decoding: document, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        let after = String(decoding: written, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(before == after)
    }

    @Test("Publication is one atomic write through the shipped seam, and nothing else")
    func publicationIsOneAtomicWriteThroughTheShippedSeam() throws {
        let fileSystem = RecordingFileSystem()

        try BrewfilePublication.publish(Data("brew \"wget\"\n".utf8), to: Self.destination, using: fileSystem)

        #expect(fileSystem.calls == [.write(Self.destination, byteCount: 12)])
    }

    /// `CatalogFileSystem` is **reused, not widened**. Its public surface must
    /// be unchanged, which is what keeps the carried follow-up S4's headroom at
    /// zero.
    @Test("The file-system seam is reused unwidened")
    func theFileSystemSeamIsReusedUnwidened() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // BrewClientTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // CellarCore
        let text = try String(
            contentsOf: root.appendingPathComponent("Sources/Catalog/CatalogFileSystem.swift"),
            encoding: .utf8
        )

        let declared = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("func ") }
            .map { String($0.dropFirst("func ".count).prefix { $0 != "(" }) }

        #expect(
            declared == [
                "createDirectory", "fileExists", "contentsMappedIfSafe",
                "write", "replaceItem", "moveItem", "removeItem"
            ],
            "the CatalogFileSystem protocol surface changed: \(declared)"
        )
        #expect(text.contains("public protocol CatalogFileSystem: Sendable"))
        // The atomicity this requirement rests on is the seam's own, unchanged.
        #expect(text.contains("try data.write(to: url, options: .atomic)"))
    }

    // MARK: - BF9 — a failure changes nothing

    @Test("A failed publication preserves the existing file")
    func aFailedPublicationPreservesTheExistingFile() throws {
        let existing = Data("brew \"already-here\"\n".utf8)
        let fileSystem = RecordingFileSystem(contents: [Self.destination: existing])
        fileSystem.failWrites(with: CocoaError(.fileWriteNoPermission))

        #expect(throws: (any Error).self) {
            try BrewfilePublication.publish(
                try Self.dumpDocument(),
                to: Self.destination,
                using: fileSystem
            )
        }

        #expect(fileSystem.bytes(at: Self.destination) == existing, "the existing file changed")
        // And nothing partial was left beside it.
        #expect(fileSystem.contents.count == 1)
        #expect(fileSystem.contents.keys.allSatisfy { $0 == Self.destination })
    }

    /// Cancelling the destination choice publishes nothing — and the temporary
    /// file is still removed, because its lifecycle belongs to the dump rather
    /// than to the panel.
    @Test("Cancelling the destination choice writes nothing and still removes the temporary")
    func cancellingTheDestinationChoiceWritesNothing() async throws {
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: try Self.dumpDocument())
        let source = BundleDumpSource(
            launcher: RecordingProcessLauncher([ScriptedRun(stdout: "", stderr: "")]),
            fileSystem: fileSystem,
            temporaryRoot: URL(fileURLWithPath: "/var/folders/xx/T")
        )

        let result = try await source.dump(for: .detected(TestInstallation.appleSilicon))

        // The panel is cancelled: `nil`, and nothing is published.
        let chooser = StubDestinationChooser(destination: nil)
        let chosen = await chooser.chooseDestination()
        #expect(chosen == nil)
        #expect(result.document.isEmpty == false)

        // Nothing was written anywhere, and the temporary directory is gone.
        #expect(fileSystem.calls.contains { call in
            if case .write = call { return true } else { return false }
        } == false)
        #expect(fileSystem.containsAnything(under: URL(fileURLWithPath: "/var/folders/xx/T")) == false)
    }

    // MARK: - BF9 — no destination is remembered

    @Test("No destination is remembered between exports")
    func noDestinationIsRememberedBetweenExports() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)

        for source in sources where source.name.hasPrefix("Brewfile") || source.name.hasPrefix("BundleDump") {
            for persistence in [
                "UserDefaults", "AppStorage", "bookmarkData", "startAccessingSecurityScopedResource",
                "NSUbiquitousKeyValueStore", "Keychain"
            ] {
                #expect(
                    source.code.containsIdentifier(persistence) == false,
                    "\(source.name) persists a destination via \(persistence)"
                )
            }
        }
    }

    @Test("No default or well-known Brewfile location can be written")
    func noDefaultOrWellKnownBrewfileLocationCanBeWritten() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)

        for source in sources where source.name.hasPrefix("Brewfile") || source.name.hasPrefix("BundleDump") {
            for wellKnown in [
                ".Brewfile", ".homebrew/Brewfile", "HOMEBREW_BUNDLE_FILE",
                "XDG_CONFIG_HOME", ".config/homebrew"
            ] {
                #expect(
                    source.code.contains(wellKnown) == false,
                    "\(source.name) names the well-known location \(wellKnown)"
                )
            }
            #expect(
                source.code.contains("homeDirectoryForCurrentUser") == false,
                "\(source.name) can derive a path in the user's home"
            )
        }

        // The only destination that exists is the one handed in.
        let publication = try #require(sources.first { $0.name == "BrewfilePublication.swift" })
        #expect(publication.code.contains("to destination: URL"))
    }

    // MARK: - DD4 — the picker seams

    @Test("The picker seams are Sendable protocols returning a plain URL")
    func thePickerSeamsAreSendableProtocolsReturningAPlainURL() async {
        let destination = StubDestinationChooser(destination: Self.destination)
        let sourceChooser = StubSourceChooser(source: Self.destination)

        #expect(await destination.chooseDestination() == Self.destination)
        #expect(await sourceChooser.chooseSource() == Self.destination)
        #expect(await StubDestinationChooser(destination: nil).chooseDestination() == nil)
        #expect(await StubSourceChooser(source: nil).chooseSource() == nil)
    }

    /// CellarCore imports **no AppKit**. The panels are the app target's job;
    /// the library only declares the seam, which is what keeps the store
    /// testable without a window server.
    @Test("CellarCore imports no AppKit anywhere on this path")
    func cellarCoreImportsNoAppKitAnywhereOnThisPath() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)

        for source in sources {
            #expect(
                source.code.contains("import AppKit") == false,
                "\(source.name) imports AppKit into CellarCore"
            )
            #expect(source.code.contains("import SwiftUI") == false)
            #expect(source.code.containsIdentifier("NSSavePanel") == false)
            #expect(source.code.containsIdentifier("NSOpenPanel") == false)
        }
    }
}

/// A destination chooser whose answer is decided before the test runs.
struct StubDestinationChooser: BrewfileDestinationChoosing {
    let destination: URL?
    func chooseDestination() async -> URL? { destination }
}

struct StubSourceChooser: BrewfileSourceChoosing {
    let source: URL?
    func chooseSource() async -> URL? { source }
}
