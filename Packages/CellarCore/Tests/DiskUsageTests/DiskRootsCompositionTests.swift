import Foundation
import Testing

@testable import BrewProcess
@testable import DiskUsage

/// The last-update reading **composes** `HomebrewRoots` and widens nothing
/// (design HD4).
///
/// Adding the repository path to `DiskRootsIdentity` was the obvious move and is
/// the wrong one, for two reasons that are cheap to state and expensive to
/// discover:
///
/// 1. `DiskRootsIdentity` is persisted verbatim as `DiskUsageSnapshot.roots`, and
///    `DiskUsageCache.load()` **throws** on a decode failure — it returns `nil`
///    only for a missing file or a schema mismatch. A new non-optional key makes
///    every previously written cache file throw `keyNotFound` rather than
///    degrade to a cold start.
/// 2. Even on a successful decode, `CleanupParser.currentlyOnDiskBytes` gates on
///    `snapshot.roots == expectedRoots`. Widening the identity changes that `==`,
///    and the orphan byte attribution silently becomes `nil` — a wrong answer
///    that looks exactly like a missing one.
///
/// This suite is the tripwire. It fails the moment somebody widens the identity,
/// which is the moment before either consequence would be noticed.
@Suite("Disk roots composition")
struct DiskRootsCompositionTests {

    private static let roots = HomebrewRoots(
        installation: BrewInstallation(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            prefix: .appleSilicon,
            version: BrewVersion(major: 6, minor: 0, patch: 15)
        ),
        userCacheDirectory: URL(fileURLWithPath: "/Users/test/Library/Caches")
    )

    /// A cache file in the shape a previous version wrote, byte for byte.
    ///
    /// Recorded as a literal rather than produced by the current encoder on
    /// purpose: a golden the code under test also generates proves only that the
    /// code agrees with itself.
    ///
    /// Note the shape of `rootStates`. `[DiskArea: DiskRootState]` encodes as a
    /// flat **array** of alternating key and value, not as an object, because
    /// `DiskArea` is not `CodingKeyRepresentable`. That is shipped behaviour and
    /// is not changed here; it is written out in full so nobody "corrects" this
    /// literal into an object and gets a decode failure they then blame on HD4.
    private static let previouslyWrittenCacheFile = """
    {"cache":{"allocatedBytes":2048,"logicalBytes":2048},"generatedAt":760000000,\
    "packages":[],"rootStates":["caskroom",{"present":{}},"cellar",{"present":{}},\
    "cache",{"present":{}}],"roots":{"cache":"\\/Users\\/test\\/Library\\/Caches\\/Homebrew",\
    "caskroom":"\\/opt\\/homebrew\\/Caskroom","cellar":"\\/opt\\/homebrew\\/Cellar",\
    "schemaVersion":1},"schemaVersion":1,"warnings":[]}
    """

    /// The `roots` sub-object exactly as the shipped encoder writes it.
    ///
    /// The byte golden is taken over **`roots` alone**, deliberately. A golden
    /// over the whole snapshot would be flaky for a reason that has nothing to do
    /// with this change: `rootStates` encodes as an array whose element order
    /// follows dictionary iteration order, and `.sortedKeys` does not sort array
    /// elements. `roots` is a struct with sorted keys and is stable — and it is
    /// the only part of the snapshot HD4 is about.
    private static let recordedRootsEncoding = """
    {"cache":"\\/Users\\/test\\/Library\\/Caches\\/Homebrew",\
    "caskroom":"\\/opt\\/homebrew\\/Caskroom","cellar":"\\/opt\\/homebrew\\/Cellar",\
    "schemaVersion":1}
    """

    // MARK: - The identity's stored-property set is unchanged

    /// Read off the encoding rather than off the declaration, because the
    /// encoding is what a previously written cache file has to agree with.
    @Test("`DiskRootsIdentity` still encodes exactly four keys")
    func theIdentityStillEncodesFourKeys() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Self.roots.identity)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(Set(object.keys) == ["schemaVersion", "cellar", "caskroom", "cache"])
        #expect(object.keys.count == 4, "the roots identity gained or lost a key")
        // And no repository, checkout or marker key crept in.
        for widened in ["repository", "checkout", "git", "fetchMarker", "lastUpdate", "prefix"] {
            #expect(object.keys.contains(widened) == false, "the identity was widened with \(widened)")
        }
    }

    @Test("`HomebrewRoots.identity` still projects the three shipped paths and nothing else")
    func theIdentityStillProjectsTheThreeShippedPaths() {
        let identity = Self.roots.identity

        #expect(identity.schemaVersion == 1)
        #expect(identity.cellar == "/opt/homebrew/Cellar")
        #expect(identity.caskroom == "/opt/homebrew/Caskroom")
        #expect(identity.cache == "/Users/test/Library/Caches/Homebrew")
    }

    // MARK: - A previously written cache file still loads

    @Test("A cache file written before this change still decodes through the shipped cache")
    func aPreviouslyWrittenCacheFileStillDecodes() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cellar-hd4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("disk-usage.json")
        try Data(Self.previouslyWrittenCacheFile.utf8).write(to: fileURL)

        // `load()` throws on a decode failure and returns `nil` only for a
        // missing file or a schema mismatch, so a widened identity surfaces here
        // as a thrown `keyNotFound` rather than as a silent cold start.
        let snapshot = try await DiskUsageCache(fileURL: fileURL).load()

        let loaded = try #require(snapshot, "a previously written cache file no longer loads")
        #expect(loaded.roots == Self.roots.identity, "the decoded roots no longer equal the live ones")
        #expect(loaded.cache.allocatedBytes == 2048, "the decode produced an empty snapshot")
        #expect(loaded.isComplete)
    }

    /// The `==` that `CleanupParser.currentlyOnDiskBytes` gates orphan-byte
    /// attribution on. A widened identity changes it, and the attribution becomes
    /// `nil` without anything failing.
    @Test("A decoded snapshot's roots still compare equal to the live roots identity")
    func decodedRootsStillCompareEqualToLiveRoots() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cellar-hd4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("disk-usage.json")
        try Data(Self.previouslyWrittenCacheFile.utf8).write(to: fileURL)
        let loaded = try #require(try await DiskUsageCache(fileURL: fileURL).load())

        #expect(loaded.roots == Self.roots.identity)
        // The control: a genuinely different prefix does **not** compare equal,
        // so the assertion above is about agreement rather than about `==`
        // having been weakened.
        let other = HomebrewRoots(
            installation: BrewInstallation(
                executableURL: URL(fileURLWithPath: "/usr/local/bin/brew"),
                prefix: .intelCarryOver,
                version: BrewVersion(major: 6, minor: 0, patch: 15)
            ),
            userCacheDirectory: URL(fileURLWithPath: "/Users/test/Library/Caches")
        )
        #expect(loaded.roots != other.identity)
    }

    /// A round trip through the shipped encoder produces the same `roots` bytes
    /// the recorded file has, so `DiskUsageSnapshot.roots` encodes identically.
    @Test("`DiskUsageSnapshot.roots` still encodes to the recorded bytes")
    func snapshotRootsStillEncodeIdentically() throws {
        let snapshot = DiskUsageSnapshot(
            roots: Self.roots.identity,
            generatedAt: Date(timeIntervalSinceReferenceDate: 760_000_000),
            rootStates: [.cellar: .present, .caskroom: .present, .cache: .present],
            packages: [],
            cache: DiskObservation(allocatedBytes: 2048, logicalBytes: 2048)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedRoots = String(decoding: try encoder.encode(snapshot.roots), as: UTF8.self)

        #expect(
            encodedRoots == Self.recordedRootsEncoding,
            "the roots encoding drifted from what a previous version wrote"
        )

        // And the recorded file still carries those exact bytes, so the golden
        // and the decode fixture cannot drift apart from each other either.
        #expect(
            Self.previouslyWrittenCacheFile.contains("\"roots\":" + Self.recordedRootsEncoding),
            "the recorded cache file and the roots golden disagree"
        )
    }

    // MARK: - The three files this change must not touch

    /// The zero-line-diff claim, asserted rather than promised. If the new
    /// reading had been bolted onto the shipped roots, one of these three would
    /// name it.
    @Test(
        "The shipped roots, models and cache name nothing from the update reading",
        arguments: ["HomebrewRoots.swift", "DiskUsageModels.swift", "DiskUsageCache.swift"]
    )
    func theShippedFilesNameNothingFromTheUpdateReading(file: String) throws {
        let source = try Self.source(of: file)

        for added in [
            "HomebrewLastUpdate", "HomebrewUpdateReader", "HomebrewRepositoryLocator",
            "FileMetadataAccess", "FileModificationDate", "FETCH_HEAD", "repository"
        ] {
            #expect(source.contains(added) == false, "\(file) was widened with \(added)")
        }
        // Positive anchor: the scan read a real file with real content, so the
        // absences above are absences rather than an unread path.
        #expect(source.isEmpty == false)
        #expect(source.contains("DiskUsage") || source.contains("HomebrewRoots"), "\(file) scan read nothing")
    }

    /// And the new reading does live somewhere: the absence above is a boundary,
    /// not a missing feature.
    @Test("The new reading lives in its own files")
    func theNewReadingLivesInItsOwnFiles() throws {
        #expect(try Self.source(of: "HomebrewUpdateReader.swift").contains("HomebrewLastUpdate"))
        #expect(try Self.source(of: "FileMetadataAccess.swift").contains("protocol FileMetadataAccess"))
    }

    private static func source(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/DiskUsage/\(file)"),
            encoding: .utf8
        )
    }
}
