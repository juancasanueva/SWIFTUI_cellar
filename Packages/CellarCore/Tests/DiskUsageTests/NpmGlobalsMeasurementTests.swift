import Catalog
import Foundation
import Testing

@testable import BrewProcess
@testable import DiskUsage

/// The npm globals root: measured only when npm is detected, represented like
/// every other root, and never double-counted against the Cellar it may live in.
///
/// The root is optional in every layer. An identity without it is what every
/// previously written cache file carries, so the key has to decode as absent
/// rather than throw; an engine without it emits no `.npm` event at all, so a
/// Mac with the source off is observably identical to a build without this
/// capability.
@Suite("npm globals measurement")
struct NpmGlobalsMeasurementTests {
    private static let installation = BrewInstallation(
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
        prefix: .appleSilicon,
        version: BrewVersion(major: 6, minor: 0, patch: 15)
    )
    private static let userCache = URL(fileURLWithPath: "/Users/test/Library/Caches")

    // MARK: - Roots and identity

    @Test("A prefix derives the globals directory under lib/node_modules")
    func prefixDerivesTheGlobalsDirectory() {
        let roots = HomebrewRoots(
            installation: Self.installation,
            userCacheDirectory: Self.userCache,
            npmPrefix: URL(fileURLWithPath: "/Users/test/.npm-global")
        )

        #expect(roots.npmGlobals?.path == "/Users/test/.npm-global/lib/node_modules")
        #expect(roots.url(for: .npm)?.path == "/Users/test/.npm-global/lib/node_modules")
        #expect(roots.identity.npmGlobals == "/Users/test/.npm-global/lib/node_modules")
    }

    @Test("Without a prefix the roots and the identity carry no npm globals")
    func withoutAPrefixNothingIsConfigured() {
        let roots = HomebrewRoots(installation: Self.installation, userCacheDirectory: Self.userCache)

        #expect(roots.npmGlobals == nil)
        #expect(roots.url(for: .npm) == nil)
        #expect(roots.identity.npmGlobals == nil)
        #expect(roots.identity.measuredAreas == [.cellar, .caskroom, .cache])
    }

    @Test("Configuring npm widens the identity, so toggling the source rescans on entry")
    func configuringNpmChangesTheIdentity() {
        let without = HomebrewRoots(installation: Self.installation, userCacheDirectory: Self.userCache)
        let with = HomebrewRoots(
            installation: Self.installation,
            userCacheDirectory: Self.userCache,
            npmPrefix: URL(fileURLWithPath: "/opt/homebrew")
        )

        #expect(with.identity != without.identity)
        #expect(with.identity.measuredAreas == [.cellar, .caskroom, .cache, .npm])
    }

    @Test("An identity encoded without npm still has exactly the four shipped keys")
    func identityWithoutNpmEncodesFourKeys() throws {
        let roots = HomebrewRoots(installation: Self.installation, userCacheDirectory: Self.userCache)
        let data = try JSONEncoder().encode(roots.identity)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(object.keys) == ["schemaVersion", "cellar", "caskroom", "cache"])
    }

    /// A cache file written before this change, byte for byte: no `npmGlobals`
    /// key in the identity and none on the snapshot.
    private static let legacyCacheFile = """
    {"cache":{"allocatedBytes":2048,"logicalBytes":2048},"generatedAt":760000000,\
    "packages":[],"rootStates":["caskroom",{"present":{}},"cellar",{"present":{}},\
    "cache",{"present":{}}],"roots":{"cache":"\\/Users\\/test\\/Library\\/Caches\\/Homebrew",\
    "caskroom":"\\/opt\\/homebrew\\/Caskroom","cellar":"\\/opt\\/homebrew\\/Cellar",\
    "schemaVersion":1},"schemaVersion":1,"warnings":[]}
    """

    @Test("A legacy snapshot without the npm keys decodes with zero npm globals")
    func legacySnapshotDecodes() throws {
        let snapshot = try JSONDecoder().decode(DiskUsageSnapshot.self, from: Data(Self.legacyCacheFile.utf8))

        #expect(snapshot.roots.npmGlobals == nil)
        #expect(snapshot.npmGlobals == .zero)
        #expect(snapshot.cache.allocatedBytes == 2048)
        #expect(snapshot.isComplete)
    }

    @Test("A snapshot with npm globals round-trips through the shipped coder")
    func snapshotWithNpmRoundTrips() throws {
        let roots = HomebrewRoots(
            installation: Self.installation,
            userCacheDirectory: Self.userCache,
            npmPrefix: URL(fileURLWithPath: "/opt/homebrew")
        )
        let snapshot = DiskUsageSnapshot(
            roots: roots.identity,
            generatedAt: Date(timeIntervalSinceReferenceDate: 760_000_000),
            rootStates: [.cellar: .present, .caskroom: .present, .cache: .present, .npm: .present],
            packages: [],
            cache: .zero,
            npmGlobals: DiskObservation(allocatedBytes: 4096, logicalBytes: 4000)
        )

        let decoded = try JSONDecoder().decode(DiskUsageSnapshot.self, from: try JSONEncoder().encode(snapshot))

        #expect(decoded == snapshot)
        #expect(decoded.npmGlobals.allocatedBytes == 4096)
    }

    // MARK: - The double-count guard

    @Test("Globals under the Cellar are flagged as lying inside it")
    func globalsInsideTheCellarAreFlagged() {
        let identity = DiskRootsIdentity(
            cellar: "/opt/homebrew/Cellar",
            caskroom: "/opt/homebrew/Caskroom",
            cache: "/Users/test/Library/Caches/Homebrew",
            npmGlobals: "/opt/homebrew/Cellar/node/24.1.0/lib/node_modules"
        )
        let snapshot = DiskUsageSnapshot(
            roots: identity, generatedAt: Date(), rootStates: [:], packages: [], cache: .zero
        )

        #expect(snapshot.npmGlobalsLiesInsideCellar)
    }

    @Test(
        "Globals elsewhere, or unconfigured, are not flagged",
        arguments: [
            nil,
            "/opt/homebrew/lib/node_modules",
            "/Users/test/.npm-global/lib/node_modules",
            // A sibling whose path merely starts with the Cellar's characters.
            "/opt/homebrew/Cellar-extra/lib/node_modules",
        ]
    )
    func globalsElsewhereAreNotFlagged(path: String?) {
        let identity = DiskRootsIdentity(
            cellar: "/opt/homebrew/Cellar",
            caskroom: "/opt/homebrew/Caskroom",
            cache: "/Users/test/Library/Caches/Homebrew",
            npmGlobals: path
        )
        let snapshot = DiskUsageSnapshot(
            roots: identity, generatedAt: Date(), rootStates: [:], packages: [], cache: .zero
        )

        #expect(snapshot.npmGlobalsLiesInsideCellar == false)
    }

    @Test("The guard compares standardized paths, not raw strings")
    func guardStandardizesPaths() {
        let identity = DiskRootsIdentity(
            cellar: "/opt/homebrew/Cellar/",
            caskroom: "/opt/homebrew/Caskroom",
            cache: "/Users/test/Library/Caches/Homebrew",
            npmGlobals: "/opt/homebrew/Cellar/node/24.1.0/../24.1.0/lib/node_modules"
        )
        let snapshot = DiskUsageSnapshot(
            roots: identity, generatedAt: Date(), rootStates: [:], packages: [], cache: .zero
        )

        #expect(snapshot.npmGlobalsLiesInsideCellar)
    }

    // MARK: - The engine

    @Test("A present globals directory is measured once as the npm area")
    func presentGlobalsAreMeasured() async throws {
        let tree = try TemporaryTree(npmGlobals: .present)
        defer { tree.remove() }
        let measurer = RecordingMeasurer(bytes: 4096)

        let events = try await collect(await DiskUsageEngine(measurer: measurer).scan(roots: tree.roots))

        #expect(events.contains { $0 == .rootCompleted(.npm, .present) })
        let snapshot = try #require(events.compactMap { event -> DiskUsageSnapshot? in
            guard case .completed(let value) = event else { return nil }
            return value
        }.first)
        #expect(snapshot.npmGlobals.allocatedBytes == 4096)
        #expect(snapshot.rootStates[.npm] == .present)
        #expect(measurer.measured(area: .npm) == [tree.roots.npmGlobals?.standardizedFileURL.path])
        #expect(snapshot.isComplete)
    }

    @Test("A missing globals directory is absent, not zero and not a failure")
    func missingGlobalsAreAbsent() async throws {
        let tree = try TemporaryTree(npmGlobals: .missing)
        defer { tree.remove() }
        let measurer = RecordingMeasurer(bytes: 4096)

        let events = try await collect(await DiskUsageEngine(measurer: measurer).scan(roots: tree.roots))

        #expect(events.contains { $0 == .rootCompleted(.npm, .absent) })
        let snapshot = try #require(events.compactMap { event -> DiskUsageSnapshot? in
            guard case .completed(let value) = event else { return nil }
            return value
        }.first)
        #expect(snapshot.npmGlobals == .zero)
        #expect(snapshot.rootStates[.npm] == .absent)
        #expect(measurer.measured(area: .npm).isEmpty)
        #expect(snapshot.isComplete)
    }

    @Test("Without a configured prefix the engine never mentions npm")
    func unconfiguredNpmIsSilent() async throws {
        let tree = try TemporaryTree(npmGlobals: .unconfigured)
        defer { tree.remove() }
        let measurer = RecordingMeasurer(bytes: 4096)

        let events = try await collect(await DiskUsageEngine(measurer: measurer).scan(roots: tree.roots))

        #expect(events.contains { if case .rootCompleted(.npm, _) = $0 { true } else { false } } == false)
        let snapshot = try #require(events.compactMap { event -> DiskUsageSnapshot? in
            guard case .completed(let value) = event else { return nil }
            return value
        }.first)
        #expect(snapshot.rootStates[.npm] == nil)
        #expect(Set(snapshot.rootStates.keys) == snapshot.roots.measuredAreas)
        #expect(snapshot.npmGlobals == .zero)
        #expect(measurer.measured(area: .npm).isEmpty)
    }

    // MARK: - Per-package sizes

    /// The four shapes a globals directory holds: a plain package, a scoped
    /// one under its `@scope` directory, npm's own `.bin`, and a package whose
    /// `package.json` is missing. Only the first three of those are counted at
    /// all, and only the first two carry a real version.
    @Test("Each global package is attributed with its package.json version")
    func globalPackagesAreAttributed() async throws {
        let tree = try TemporaryTree(npmGlobals: .present)
        defer { tree.remove() }
        try tree.writeGlobal("typescript/package.json", contents: #"{"name":"typescript","version":"5.9.2","bin":{}}"#)
        try tree.writeGlobal("@angular/cli/package.json", contents: #"{"version":"20.1.0"}"#)
        try tree.writeGlobal("broken/index.js", contents: "module.exports = {}")
        try tree.writeGlobal(".bin/tsc", contents: "#!/bin/sh")
        try tree.writeGlobal(".package-lock.json", contents: "{}")
        let measurer = RecordingMeasurer(bytes: 100)

        let events = try await collect(await DiskUsageEngine(measurer: measurer).scan(roots: tree.roots))

        let packages = events.compactMap { event -> DiskPackageUsage? in
            guard case .package(let value) = event, value.id.kind == .npm else { return nil }
            return value
        }
        let byName = Dictionary(uniqueKeysWithValues: packages.map { ($0.id.name, $0) })
        #expect(Set(byName.keys) == ["typescript", "@angular/cli", "broken"])
        #expect(byName["typescript"]?.versions.map(\.id.rawVersion) == ["5.9.2"])
        #expect(byName["@angular/cli"]?.versions.map(\.id.rawVersion) == ["20.1.0"])
        #expect(byName["broken"]?.versions.map(\.id.rawVersion) == ["unknown"])
        #expect(packages.allSatisfy { $0.versions.count == 1 })
        #expect(packages.allSatisfy { $0.versions.allSatisfy { $0.linkState == .notApplicable } })
        #expect(packages.allSatisfy { $0.observation.allocatedBytes == 100 })

        let versions = events.compactMap { event -> DiskVersionUsage? in
            guard case .version(let value) = event, value.id.package.kind == .npm else { return nil }
            return value
        }
        #expect(versions.count == 3)

        // The scope directory itself is never a package, and dot entries are
        // never measured.
        let measured = measurer.measured(area: .npm)
        #expect(measured.contains { $0.hasSuffix("/node_modules/@angular") } == false)
        #expect(measured.contains { $0.contains("/.bin") } == false)
        #expect(measured.count == 4, "three packages plus the root total")

        let snapshot = try #require(events.compactMap { event -> DiskUsageSnapshot? in
            guard case .completed(let value) = event else { return nil }
            return value
        }.first)
        #expect(snapshot.packages.filter { $0.id.kind == .npm }.count == 3)
        #expect(snapshot.npmGlobals.allocatedBytes == 100, "the root total is still measured as one unit")
        #expect(snapshot.rootStates[.npm] == .present)
        #expect(snapshot.warnings.isEmpty, "a missing package.json is not a measurement failure")

        let progress = events.compactMap { event -> DiskUsageProgress? in
            guard case .progress(let value) = event else { return nil }
            return value
        }
        let last = try #require(progress.last)
        // Three versions, three packages and the root: seven units, all done.
        #expect(last.discoveredUnits == 7)
        #expect(last.completedUnits == 7)
    }

    /// The failure is a regular file where the directory should be: it exists,
    /// so the root is not absent, and it cannot be enumerated, so the root
    /// fails. Deterministic on every host, unlike a permission bit that root
    /// ignores.
    @Test("A globals path that cannot be enumerated fails the root and names it")
    func unenumerableGlobalsFailTheRoot() async throws {
        let tree = try TemporaryTree(npmGlobals: .file)
        defer { tree.remove() }
        let globals = try #require(tree.roots.npmGlobals)
        let measurer = RecordingMeasurer(bytes: 1)

        let events = try await collect(await DiskUsageEngine(measurer: measurer).scan(roots: tree.roots))

        let state = events.compactMap { event -> DiskRootState? in
            guard case .rootCompleted(.npm, let state) = event else { return nil }
            return state
        }.first
        guard case .failed(let message) = state else {
            Issue.record("expected .failed, got \(String(describing: state))")
            return
        }
        #expect(message.isEmpty == false)
        let warnings = events.compactMap { event -> DiskUsageWarning? in
            guard case .warning(let value) = event, value.area == .npm else { return nil }
            return value
        }
        #expect(warnings.map(\.path) == [globals.path])
        #expect(warnings.first?.message == message)
        #expect(measurer.measured(area: .npm).isEmpty, "nothing under a failed root is measured")
        let snapshot = try #require(events.compactMap { event -> DiskUsageSnapshot? in
            guard case .completed(let value) = event else { return nil }
            return value
        }.first)
        #expect(snapshot.rootStates[.npm] == .failed(message))
        #expect(snapshot.npmGlobals == .zero)
        #expect(snapshot.isComplete == false)
    }

    private func collect(_ stream: DiskUsageEventStream) async throws -> [DiskUsageEvent] {
        var events: [DiskUsageEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }
}

// MARK: - Support

/// Answers a fixed size for every directory and records what it was asked to
/// measure, so a claim about the npm area is a claim about one call with one
/// path rather than about the bytes some temporary file happened to occupy.
private final class RecordingMeasurer: DirectoryMeasuring, @unchecked Sendable {
    private let bytes: Int64
    private let lock = NSLock()
    private var calls: [(DiskArea, String)] = []

    init(bytes: Int64) { self.bytes = bytes }

    func measure(_ root: URL, area: DiskArea) throws -> DirectoryMeasurement {
        lock.withLock { calls.append((area, root.standardizedFileURL.path)) }
        return DirectoryMeasurement(observation: DiskObservation(allocatedBytes: bytes, logicalBytes: bytes))
    }

    func measured(area: DiskArea) -> [String] {
        lock.withLock { calls.filter { $0.0 == area }.map(\.1) }
    }
}

private struct TemporaryTree {
    enum NpmGlobals { case present, missing, unconfigured, file }

    let base: URL
    let roots: HomebrewRoots

    init(npmGlobals: NpmGlobals) throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Cellar"), withIntermediateDirectories: true)
        let npmPrefix = base.appendingPathComponent("npm", isDirectory: true)
        switch npmGlobals {
        case .present:
            try FileManager.default.createDirectory(
                at: npmPrefix.appendingPathComponent("lib/node_modules"),
                withIntermediateDirectories: true
            )
        case .file:
            try FileManager.default.createDirectory(
                at: npmPrefix.appendingPathComponent("lib"),
                withIntermediateDirectories: true
            )
            try Data("not a directory".utf8).write(to: npmPrefix.appendingPathComponent("lib/node_modules"))
        case .missing, .unconfigured:
            break
        }
        let installation = BrewInstallation(
            executableURL: base.appendingPathComponent("bin/brew"),
            prefix: .custom(base),
            version: BrewVersion(major: 6, minor: 0, patch: 15)
        )
        roots = HomebrewRoots(
            installation: installation,
            userCacheDirectory: base.appendingPathComponent("UserCaches", isDirectory: true),
            npmPrefix: npmGlobals == .unconfigured ? nil : npmPrefix
        )
    }

    func writeGlobal(_ relativePath: String, contents: String) throws {
        let url = base.appendingPathComponent("npm/lib/node_modules").appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    func remove() { try? FileManager.default.removeItem(at: base) }
}
