import BrewProcess
import Catalog
import DiskUsage
import Foundation
import Testing
@testable import BrewClient
@Suite("Cleanup parser and evidence")
struct CleanupParserTests {
    struct FixtureCase: Sendable, CustomTestStringConvertible {
        let name: String
        let isStderr: Bool
        let scope: CleanupScope
        var testDescription: String { name }
    }
    static let fixtureCases = [
        FixtureCase(name: "autoremove-dry-run.stdout", isStderr: false, scope: .autoremove), FixtureCase(name: "autoremove-dry-run.stderr", isStderr: true, scope: .autoremove),
        FixtureCase(name: "cleanup-full-dry-run.stdout", isStderr: false, scope: .full), FixtureCase(name: "cleanup-full-dry-run.stderr", isStderr: true, scope: .full),
        FixtureCase(name: "cleanup-full.stdout", isStderr: false, scope: .full), FixtureCase(name: "cleanup-full.stderr", isStderr: true, scope: .full),
        FixtureCase(name: "cleanup-global-dry-run.stdout", isStderr: false, scope: .global), FixtureCase(name: "cleanup-global-dry-run.stderr", isStderr: true, scope: .global),
        FixtureCase(name: "contention-held.stdout", isStderr: false, scope: .full), FixtureCase(name: "contention-held.stderr", isStderr: true, scope: .full),
        FixtureCase(name: "contention-released.stdout", isStderr: false, scope: .full), FixtureCase(name: "contention-released.stderr", isStderr: true, scope: .full),
        FixtureCase(name: "contention.txt", isStderr: false, scope: .full), FixtureCase(name: "probe-manifest.txt", isStderr: false, scope: .full),
    ]
    @Test("All U0 fixtures survive byte-exact parsing", arguments: fixtureCases)
    func u0FixtureBytesSurvive(_ fixtureCase: FixtureCase) throws {
        let bytes = try fixture(fixtureCase.name)
        let request = CleanupPreviewRequest(scope: fixtureCase.scope)
        let result = CleanupParser.parse(
            request,
            rawStdout: fixtureCase.isStderr ? Data() : bytes,
            rawStderr: fixtureCase.isStderr ? bytes : Data()
        )
        #expect(result.rawStdout == (fixtureCase.isStderr ? Data() : bytes))
        #expect(result.rawStderr == (fixtureCase.isStderr ? bytes : Data()))
    }
    @Test("Fixture-backed cleanup rows and footer retain provenance")
    func cleanupRowsAndFooter() throws {
        let stdout = try fixture("cleanup-full-dry-run.stdout")
        let result = CleanupParser.parse(
            CleanupPreviewRequest(scope: .full),
            rawStdout: stdout,
            rawStderr: Data()
        )
        #expect(result.evidence.rows.map(\.bytes) == [12, 10])
        #expect(result.evidence.total == .reportedFooter(bytes: 22))
        #expect(result.provenance.parserVersion == 2)
        #expect(result.provenance.footerForm == .wouldFree)
        #expect(result.evidence.isPartial == false)
    }
    @Test("Missing footer stays unknown and never becomes the row sum")
    func missingFooterDoesNotSumRows() {
        let stdout = Data("Would remove: /tmp/a (12B)\nWould remove: /tmp/b (10B)\n".utf8)
        let result = CleanupParser.parse(
            CleanupPreviewRequest(scope: .full),
            rawStdout: stdout,
            rawStderr: Data()
        )
        #expect(result.evidence.rows.map(\.bytes) == [12, 10])
        #expect(result.evidence.total == .unknown)
        #expect(result.evidence.isPartial == false)
    }
    @Test("A keg row's file count is not part of its size")
    func kegRowFileCountIsNotPartOfItsSize() {
        // Cellar keg rows carry a file count before the size; cache rows carry
        // the size alone. Both are complete evidence — treating the keg shape
        // as malformed is what turned every preview on a machine with old kegs
        // partial, and partial means cleanup refuses.
        let stdout = Data(
            """
            Would remove: /opt/homebrew/Cellar/ca-certificates/2026-07-16 (4 files, 197.9KB)
            Would remove: /opt/homebrew/Cellar/openssl@3/3.3.1 (1 file, 12B)
            Would remove: /opt/homebrew/Cellar/gcc/14.2.0 (1,050 files, 9.5MB)
            Would remove: /tmp/cache/druk--1.16.0.arm64.bottle.tar.gz (30.9MB)
            """.utf8
        )
        let result = CleanupParser.parse(
            CleanupPreviewRequest(scope: .global),
            rawStdout: stdout,
            rawStderr: Data()
        )
        #expect(result.evidence.rows.map(\.bytes) == [202_650, 12, 9_961_472, 32_400_998])
        #expect(result.evidence.issues.isEmpty)
        #expect(result.evidence.isPartial == false)
    }
    @Test("A parenthetical with a non-count prefix stays malformed")
    func nonCountParentheticalStaysMalformed() {
        let stdout = Data("Would remove: /tmp/a (weird, 12B)\n".utf8)
        let result = CleanupParser.parse(
            CleanupPreviewRequest(scope: .global),
            rawStdout: stdout,
            rawStderr: Data()
        )
        #expect(result.evidence.rows.isEmpty)
        #expect(result.evidence.issues == [.malformedSize])
    }
    @Test("Empty-directory lines are typed evidence, not unknown output")
    func emptyDirectoryLinesAreTyped() {
        // Homebrew's cleanup.rb prints `Would remove (empty directory): #{d}`
        // in dry-run mode only; the real run removes the directory silently.
        let stdout = Data(
            "Would remove (empty directory): /opt/homebrew/lib/ruby/gems/3.3.0/doc/cocoapods-1.16.2\n"
                .appending("Would remove: /tmp/a (12B)\n")
                .utf8
        )
        let result = CleanupParser.parse(
            CleanupPreviewRequest(scope: .global),
            rawStdout: stdout,
            rawStderr: Data()
        )
        #expect(result.evidence.emptyDirectories == ["/opt/homebrew/lib/ruby/gems/3.3.0/doc/cocoapods-1.16.2"])
        #expect(result.evidence.rows.map(\.bytes) == [12])
        #expect(result.evidence.unknownLines.isEmpty)
        #expect(result.evidence.isPartial == false)
    }
    @Test("Empty directories alone are cleanable, never an empty preview or an invented size")
    func emptyDirectoriesAloneAreNotEmpty() {
        let stdout = Data("Would remove (empty directory): /tmp/dir\n".utf8)
        let result = CleanupParser.parse(
            CleanupPreviewRequest(scope: .full),
            rawStdout: stdout,
            rawStderr: Data()
        )
        #expect(result.evidence.rows.isEmpty)
        #expect(result.evidence.emptyDirectories == ["/tmp/dir"])
        #expect(result.evidence.isEmpty == false)
        #expect(result.evidence.isPartial == false)
        #expect(result.evidence.total == .unknown)
    }
    @Test("Empty directories carry authorization identity")
    func emptyDirectoriesCarryIdentity() {
        let first = cleanup("Would remove (empty directory): /tmp/a\n")
        let same = cleanup("Would remove (empty directory): /tmp/a\n")
        let changed = cleanup("Would remove (empty directory): /tmp/b\n")
        #expect(first.evidence.isEqualForAuthorization(to: same.evidence))
        #expect(first.evidence.fingerprint == same.evidence.fingerprint)
        #expect(first.evidence.isEqualForAuthorization(to: changed.evidence) == false)
        #expect(first.evidence.fingerprint != changed.evidence.fingerprint)
    }
    @Test("Overflow, malformed size, and unknown nonblank lines are partial")
    func malformedInputIsPartial() {
        let stdout = Data(
            "Would remove: /tmp/huge (9223372036854775808B)\n"
                .appending("Would remove: /tmp/bad (many bytes)\n")
                .appending("Would remove (empty directory): \n")
                .appending("future Homebrew prose\n")
                .utf8
        )
        let result = CleanupParser.parse(
            CleanupPreviewRequest(scope: .global),
            rawStdout: stdout,
            rawStderr: Data()
        )
        #expect(result.evidence.rows.isEmpty)
        #expect(result.evidence.emptyDirectories.isEmpty)
        #expect(result.evidence.unknownLines.count == 4)
        #expect(result.evidence.unknownLines[0] == Data("Would remove: /tmp/huge (9223372036854775808B)\n".utf8))
        #expect(result.evidence.issues.contains(.malformedSize))
        #expect(result.evidence.issues.contains(.unknownLine))
        #expect(result.evidence.isPartial)
    }
    @Test("Blank autoremove is exactly zero candidates")
    func blankAutoremoveIsZero() {
        let result = CleanupParser.parse(
            CleanupPreviewRequest(scope: .autoremove),
            rawStdout: Data(),
            rawStderr: Data()
        )
        #expect(result.evidence.orphans == .known(names: [], reportedCount: 0, currentlyOnDiskBytes: nil))
        #expect(result.evidence.isEmpty)
        #expect(result.evidence.isPartial == false)
    }
    @Test("Autoremove preserves exact names and detects count mismatch")
    func autoremoveNamesAndCount() {
        let exact = autoremove("==> Would autoremove 2 unneeded formulae:\nlibthai\npango\n")
        let mismatch = autoremove("==> Would autoremove 3 unneeded formulae:\nlibthai\npango\n")
        #expect(exact.evidence.orphans == .known(
            names: ["libthai", "pango"],
            reportedCount: 2,
            currentlyOnDiskBytes: nil
        ))
        #expect(exact.evidence.isPartial == false)
        #expect(mismatch.evidence.orphans == .known(
            names: ["libthai", "pango"],
            reportedCount: 3,
            currentlyOnDiskBytes: nil
        ))
        #expect(mismatch.evidence.issues.contains(.orphanCountMismatch))
        #expect(mismatch.evidence.isPartial)
    }
    @Test("Authorization identity is typed equality while fingerprints are canonical diagnostics")
    func equalityAndFingerprintIdentity() {
        let first = autoremove("==> Would autoremove 1 unneeded formula:\nlibthai\n", id: UUID())
        let sameEvidence = autoremove("==> Would autoremove 1 unneeded formula:\nlibthai\n", id: UUID())
        let changed = autoremove("==> Would autoremove 1 unneeded formula:\npango\n", id: UUID())
        #expect(first.requestID != sameEvidence.requestID)
        #expect(first.evidence.isEqualForAuthorization(to: sameEvidence.evidence))
        #expect(first.evidence.fingerprint == sameEvidence.evidence.fingerprint)
        #expect(first.evidence.isEqualForAuthorization(to: changed.evidence) == false)
        #expect(first.evidence.fingerprint != changed.evidence.fingerprint)
        #expect(first.evidence.fingerprint.version == 2)
        #expect(first.evidence.fingerprint.hexadecimal.count == 64)
    }
    @Test("Only a complete same-root snapshot supplies currently-on-disk orphan allocation")
    func allocationRequiresCompleteSameRootSnapshot() {
        let roots = DiskRootsIdentity(cellar: "/a/Cellar", caskroom: "/a/Caskroom", cache: "/a/Cache")
        let complete = snapshot(roots: roots, warning: false)
        let incomplete = snapshot(roots: roots, warning: true)
        let wrongRoots = DiskRootsIdentity(cellar: "/b/Cellar", caskroom: "/b/Caskroom", cache: "/b/Cache")
        let stdout = Data("==> Would autoremove 2 unneeded formulae:\nlibthai\npango\n".utf8)
        let allocated = autoremove(stdout, snapshot: complete, roots: roots)
        let partial = autoremove(stdout, snapshot: incomplete, roots: roots)
        let wrongRoot = autoremove(stdout, snapshot: complete, roots: wrongRoots)
        #expect(allocated.evidence.orphans.currentlyOnDiskBytes == 30)
        #expect(partial.evidence.orphans.currentlyOnDiskBytes == nil)
        #expect(wrongRoot.evidence.orphans.currentlyOnDiskBytes == nil)
        #expect(allocated.evidence.total == .unknown, "disk allocation became reclaimable provenance")
    }
    private func cleanup(_ text: String) -> CleanupPreviewResult {
        CleanupParser.parse(
            CleanupPreviewRequest(scope: .global),
            rawStdout: Data(text.utf8),
            rawStderr: Data()
        )
    }
    private func autoremove(_ text: String, id: UUID = UUID()) -> CleanupPreviewResult {
        CleanupParser.parse(
            CleanupPreviewRequest(id: id, scope: .autoremove),
            rawStdout: Data(text.utf8),
            rawStderr: Data()
        )
    }
    private func autoremove(
        _ stdout: Data,
        snapshot: DiskUsageSnapshot,
        roots: DiskRootsIdentity
    ) -> CleanupPreviewResult {
        CleanupParser.parse(
            CleanupPreviewRequest(scope: .autoremove), rawStdout: stdout, rawStderr: Data(),
            diskUsage: .init(snapshot: snapshot, expectedRoots: roots)
        )
    }
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Cleanup")
        )
        return try Data(contentsOf: url)
    }
    private func snapshot(roots: DiskRootsIdentity, warning: Bool) -> DiskUsageSnapshot {
        DiskUsageSnapshot(
            roots: roots,
            generatedAt: Date(timeIntervalSince1970: 1),
            rootStates: [
                .cellar: .present,
                .caskroom: .present,
                .cache: warning ? .failed("denied") : .present,
            ],
            packages: [package("libthai", bytes: 12), package("pango", bytes: 18)],
            cache: .zero,
            warnings: warning ? [.init(area: .cache, path: roots.cache, message: "denied")] : []
        )
    }
    private func package(_ name: String, bytes: Int64) -> DiskPackageUsage {
        let id = PackageID(kind: .formula, name: name)
        return DiskPackageUsage(
            id: id,
            versions: [.init(
                id: .init(package: id, rawVersion: "1"),
                observation: .init(allocatedBytes: bytes, logicalBytes: bytes),
                linkState: .unlinked
            )]
        )
    }
}
