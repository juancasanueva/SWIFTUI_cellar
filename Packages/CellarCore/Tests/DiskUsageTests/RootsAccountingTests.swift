import Foundation
import Testing

@testable import BrewProcess
@testable import DiskUsage

@Suite("Disk usage roots and accounting")
struct RootsAccountingTests {
    @Test("Validated standard and custom installations derive independent roots")
    func rootsComeOnlyFromValidatedInstallations() {
        let standard = HomebrewRoots(
            installation: installation("/opt/homebrew/bin/brew"),
            userCacheDirectory: URL(fileURLWithPath: "/Users/test/Library/Caches")
        )
        let custom = HomebrewRoots(
            installation: installation("/Volumes/Tools/homebrew/bin/brew"),
            userCacheDirectory: URL(fileURLWithPath: "/tmp/cache")
        )

        #expect(standard.prefix.path == "/opt/homebrew")
        #expect(standard.cellar.path == "/opt/homebrew/Cellar")
        #expect(standard.caskroom.path == "/opt/homebrew/Caskroom")
        #expect(standard.cache.path == "/Users/test/Library/Caches/Homebrew")
        #expect(custom.cellar.path == "/Volumes/Tools/homebrew/Cellar")
        #expect(custom.identity != standard.identity)
    }

    @Test("Missing roots are represented independently instead of fabricated as zero")
    func rootStatesAreIndependent() async throws {
        let prefix = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: prefix.appendingPathComponent("Cellar", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: prefix) }
        let roots = HomebrewRoots(
            installation: installation(prefix.appendingPathComponent("bin/brew").path),
            userCacheDirectory: prefix.appendingPathComponent("UserCaches", isDirectory: true)
        )

        var completed: DiskUsageSnapshot?
        for try await event in await DiskUsageEngine().scan(roots: roots) {
            if case .completed(let snapshot) = event { completed = snapshot }
        }

        let states = try #require(completed?.rootStates)
        #expect(states[.cellar] == .present)
        #expect(states[.caskroom] == .absent)
        #expect(states[.cache] == .absent)
        // An unconfigured npm root is not a missing one: it has no state at all.
        #expect(states[.npm] == nil)
    }

    @Test("Cask application bundle descendants contribute their allocation")
    func caskBundleDescendantsAreMeasured() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payload = directory.appendingPathComponent("Ghostty.app/Contents/MacOS/ghostty")
        try FileManager.default.createDirectory(
            at: payload.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 1, count: 4_096).write(to: payload)

        let result = try MetadataDirectoryMeasurer().measure(directory, area: .caskroom)

        #expect(result.observation.logicalBytes == 4_096)
        #expect(result.observation.allocatedBytes >= 4_096)
        #expect(result.warning == nil)
    }

    @Test("Metadata traversal deduplicates hard links and never follows symbolic links")
    func metadataTraversalIsLinkSafe() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("payload")
        try Data("abcdef".utf8).write(to: original)
        try FileManager.default.linkItem(at: original, to: directory.appendingPathComponent("hard-link"))
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("symbolic-link"),
            withDestinationURL: original
        )

        let result = try MetadataDirectoryMeasurer().measure(directory, area: .cache)

        #expect(result.observation.logicalBytes == 6)
        #expect(result.observation.allocatedBytes >= 6)
        #expect(result.warning == nil)
    }

    private func installation(_ path: String) -> BrewInstallation {
        BrewInstallation(
            executableURL: URL(fileURLWithPath: path),
            prefix: .custom(URL(fileURLWithPath: path)),
            version: BrewVersion(major: 6, minor: 0, patch: 15)
        )
    }
}
