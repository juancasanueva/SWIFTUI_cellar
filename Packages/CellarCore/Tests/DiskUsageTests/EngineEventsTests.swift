import Catalog
import Foundation
import Testing

@testable import BrewProcess
@testable import DiskUsage

@Suite("Disk usage engine events")
struct EngineEventsTests {
    @Test("Formula and cask versions are attributed from raw path components")
    func engineAttributesPackagesAndVersions() async throws {
        let tree = try TemporaryHomebrewTree()
        defer { tree.remove() }
        try tree.write("Cellar/wget/1.2.3/bin/wget", bytes: 7)
        try tree.write("Caskroom/ghostty/1.0/Ghostty.app/file", bytes: 11)
        try tree.writeCache("downloads/archive", bytes: 13)

        let events = try await collect(
            await DiskUsageEngine().scan(
                roots: tree.roots,
                formulaLinks: [PackageID(kind: .formula, name: "wget"): .linked("1.2.3")]
            )
        )

        let versions = events.compactMap { event -> DiskVersionUsage? in
            guard case .version(let value) = event else { return nil }
            return value
        }
        #expect(versions.map(\.id.rawVersion).sorted() == ["1.0", "1.2.3"])
        #expect(versions.first { $0.id.package.name == "wget" }?.linkState == .linked("1.2.3"))
        #expect(events.contains { if case .completed = $0 { true } else { false } })
    }

    @Test("Missing roots are independent and progress is unit bounded")
    func missingRootsAndProgressRemainBounded() async throws {
        let tree = try TemporaryHomebrewTree(createCaskroom: false)
        defer { tree.remove() }
        try tree.write("Cellar/a/1/file", bytes: 1)

        let events = try await collect(await DiskUsageEngine().scan(roots: tree.roots))
        let progress = events.compactMap { event -> DiskUsageProgress? in
            guard case .progress(let value) = event else { return nil }
            return value
        }

        #expect(progress.isEmpty == false)
        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0.completedUnits <= $1.completedUnits })
        #expect(events.contains { $0 == .rootCompleted(.caskroom, .absent) })
    }

    private func collect(
        _ stream: AsyncThrowingStream<DiskUsageEvent, any Error>
    ) async throws -> [DiskUsageEvent] {
        var events: [DiskUsageEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }
}

private struct TemporaryHomebrewTree {
    let base: URL
    let userCache: URL
    let roots: HomebrewRoots

    init(createCaskroom: Bool = true) throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        userCache = base.appendingPathComponent("UserCaches")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Cellar"), withIntermediateDirectories: true)
        if createCaskroom {
            try FileManager.default.createDirectory(at: base.appendingPathComponent("Caskroom"), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: userCache.appendingPathComponent("Homebrew"), withIntermediateDirectories: true)
        let installation = BrewInstallation(
            executableURL: base.appendingPathComponent("bin/brew"),
            prefix: .custom(base),
            version: BrewVersion(major: 6, minor: 0, patch: 15)
        )
        roots = HomebrewRoots(installation: installation, userCacheDirectory: userCache)
    }

    func write(_ relativePath: String, bytes: Int) throws {
        try write(at: base.appendingPathComponent(relativePath), bytes: bytes)
    }

    func writeCache(_ relativePath: String, bytes: Int) throws {
        try write(at: userCache.appendingPathComponent("Homebrew").appendingPathComponent(relativePath), bytes: bytes)
    }

    private func write(at url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
    }

    func remove() { try? FileManager.default.removeItem(at: base) }
}
