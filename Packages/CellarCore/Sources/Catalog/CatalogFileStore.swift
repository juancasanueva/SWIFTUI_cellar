import Foundation

/// Reads and writes the two files that make up the persisted catalog.
///
/// `catalog.json` is the snapshot; `catalog-state.json` is the sidecar that says
/// how fresh it is and which validators to replay. They are always published in
/// that order (design D3).
public struct CatalogFileStore: Sendable {
    public let directory: URL
    private let fileSystem: any CatalogFileSystem
    /// The version this build can read. Exact in both directions: older and
    /// newer are the same answer, "no cache".
    ///
    /// Injectable, and internal rather than public, for exactly one reason — the
    /// rollback-symmetry test has to observe what a *reverted* build sees
    /// without editing the constant it is testing. The public initializer's
    /// signature is unchanged.
    let expectedSchemaVersion: Int

    public init(directory: URL, fileSystem: any CatalogFileSystem = DefaultCatalogFileSystem()) {
        self.init(
            directory: directory,
            fileSystem: fileSystem,
            expectedSchemaVersion: CatalogSnapshot.currentSchemaVersion
        )
    }

    init(
        directory: URL,
        fileSystem: any CatalogFileSystem = DefaultCatalogFileSystem(),
        expectedSchemaVersion: Int
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.expectedSchemaVersion = expectedSchemaVersion
    }

    public var snapshotURL: URL { directory.appendingPathComponent("catalog.json") }
    public var stateURL: URL { directory.appendingPathComponent("catalog-state.json") }
    /// The undated seen-set. Versioned by `DiscoverySchema`, not by the
    /// snapshot's schema, so the two gate independently.
    public var rosterURL: URL { directory.appendingPathComponent("catalog-roster.json") }
    public var arrivalsURL: URL { directory.appendingPathComponent("catalog-arrivals.json") }
    public var stagingURL: URL { directory.appendingPathComponent("staging", isDirectory: true) }

    /// Whether a snapshot this build can actually read is on disk.
    public var hasUsableCache: Bool {
        ((try? loadSnapshot()) ?? nil) != nil
    }

    // MARK: - Reading

    /// The persisted snapshot, or `nil` when there is nothing this build can use.
    ///
    /// A missing, corrupt or newer-schema file is all the same answer: no cache.
    /// The catalog is derived data, always re-acquirable, so refusing to launch
    /// over it would be a self-inflicted outage (catalog-sync CS6).
    public func loadSnapshot() throws -> CatalogSnapshot? {
        guard let data = try? fileSystem.contentsMappedIfSafe(of: snapshotURL) else { return nil }
        guard records(expectedSchemaVersion, in: data) else { return nil }
        guard let snapshot = try? decoder.decode(CatalogSnapshot.self, from: data) else { return nil }
        // A catalog with no packages is degenerate, and answering with it would
        // leave the machine revalidating into emptiness forever: the stored
        // validators would still certify it, the origin would answer 304, and
        // nothing would ever rebuild. Classified as no cache, exactly like a
        // missing or newer-schema file, which is the existing CS6 path that
        // forces an unconditional re-download. The file is left where it is —
        // a read must not mutate the store (design D4).
        guard !snapshot.packages.isEmpty else { return nil }
        return snapshot
    }

    public func loadState() throws -> CatalogState? {
        guard let data = try? fileSystem.contentsMappedIfSafe(of: stateURL) else { return nil }
        guard records(expectedSchemaVersion, in: data) else { return nil }
        return try? decoder.decode(CatalogState.self, from: data)
    }

    /// The set of identities this machine has already observed, or `nil`.
    ///
    /// Missing, corrupt and version-mismatched are deliberately the **same**
    /// answer, "seen nothing" — and by the seeding rule in
    /// `DiscoveryRosterDiff`, that answer produces zero arrivals rather than
    /// reporting the whole catalog as new. Non-throwing by signature, because
    /// "MUST NOT be reported as an error" is stronger as a type than as a
    /// convention (catalog-sync CS-A1).
    ///
    /// Gated against `DiscoverySchema.currentVersion` and never against the
    /// snapshot's: a snapshot bump must not erase a user's history.
    public func loadRoster() -> KnownPackageRoster? {
        guard let data = try? fileSystem.contentsMappedIfSafe(of: rosterURL) else { return nil }
        guard records(DiscoverySchema.currentVersion, in: data) else { return nil }
        return try? decoder.decode(KnownPackageRoster.self, from: data)
    }

    /// The dated arrivals log, or `nil` for "no arrivals".
    ///
    /// Gated exactly as the roster is, and independently of it: a corrupt
    /// arrivals log costs arrivals without costing the seen-set (CS-A2).
    public func loadArrivals() -> PackageArrivalsLog? {
        guard let data = try? fileSystem.contentsMappedIfSafe(of: arrivalsURL) else { return nil }
        guard records(DiscoverySchema.currentVersion, in: data) else { return nil }
        return try? decoder.decode(PackageArrivalsLog.self, from: data)
    }

    /// Whether a persisted file records exactly the version its owning schema
    /// expects.
    ///
    /// Takes the expected version rather than reading `expectedSchemaVersion`
    /// implicitly, which is what lets the snapshot, the state sidecar and the
    /// two newness sidecars share one gate while answering to **different**
    /// schemas. Reads only the version field, so a payload whose other fields
    /// this build cannot parse is still classified correctly, and the check is
    /// exact in both directions — older and newer are the same answer.
    private func records(_ expected: Int, in data: Data) -> Bool {
        struct VersionProbe: Decodable { let schemaVersion: Int }
        return (try? decoder.decode(VersionProbe.self, from: data))?.schemaVersion == expected
    }

    // MARK: - Writing

    /// Publishes a snapshot and its sidecar, snapshot first.
    ///
    /// A crash between the two leaves a fresh catalog advertised with stale
    /// validators, which costs one redundant download. The reverse order would
    /// advertise a stale catalog as fresh, which serves wrong data (design D3).
    public func persist(_ snapshot: CatalogSnapshot, state: CatalogState) throws {
        // Outside the `do` on purpose: that block rewrites every throw to
        // `.persistence`, and this is a semantic refusal, not an I/O failure.
        // No code path in this package can write an empty catalog (design D4).
        guard !snapshot.packages.isEmpty else { throw CatalogSyncError.malformedPayload }

        do {
            try fileSystem.createDirectory(at: directory)
            try publish(try encoder.encode(snapshot), to: snapshotURL, stagedAs: "catalog.json.new")
            try publish(try encoder.encode(state), to: stateURL, stagedAs: "catalog-state.json.new")
        } catch {
            throw CatalogSyncError.persistence
        }
    }

    /// Publishes only the sidecar.
    ///
    /// The path a fully revalidated sync takes: nothing about the 4 MB snapshot
    /// changed, but its freshness did (catalog-sync CS2).
    public func persistState(_ state: CatalogState) throws {
        do {
            try fileSystem.createDirectory(at: directory)
            try publish(try encoder.encode(state), to: stateURL, stagedAs: "catalog-state.json.new")
        } catch {
            throw CatalogSyncError.persistence
        }
    }

    /// Publishes the two newness sidecars, **arrivals first**.
    ///
    /// The crash-order choice, mirroring the snapshot-before-sidecar rule: pick
    /// the order that costs a redundant repeat rather than a wrong answer. A
    /// crash between the two leaves an arrival recorded whose identity the
    /// roster does not yet hold, so the next sync records it again and the
    /// earliest-`firstSeenAt` rule deduplicates it. Writing the roster first
    /// would mark the package seen with no arrival ever written, losing it
    /// permanently (catalog-sync CS-A1, CS-A2).
    public func persistDiscovery(roster: KnownPackageRoster, arrivals: PackageArrivalsLog) throws {
        do {
            try fileSystem.createDirectory(at: directory)
            try publish(
                try encoder.encode(arrivals),
                to: arrivalsURL,
                stagedAs: "catalog-arrivals.json.new"
            )
            try publish(
                try encoder.encode(roster),
                to: rosterURL,
                stagedAs: "catalog-roster.json.new"
            )
        } catch {
            throw CatalogSyncError.persistence
        }
    }

    private func publish(_ data: Data, to destination: URL, stagedAs name: String) throws {
        let staged = directory.appendingPathComponent(name)
        try fileSystem.write(data, to: staged)
        do {
            try fileSystem.replaceItem(at: destination, withItemAt: staged)
        } catch {
            // The half-written temp file must not survive to confuse the next run.
            try? fileSystem.removeItem(at: staged)
            throw error
        }
    }

    // MARK: - Staging

    /// A clean directory for in-flight downloads.
    @discardableResult
    public func prepareStaging() throws -> URL {
        purgeStaging()
        do {
            try fileSystem.createDirectory(at: stagingURL)
        } catch {
            throw CatalogSyncError.persistence
        }
        return stagingURL
    }

    /// Removes the whole staging subtree.
    ///
    /// Called on success, failure and cancellation alike: a partially downloaded
    /// 31 MB payload has no value to anyone.
    public func purgeStaging() {
        guard fileSystem.fileExists(at: stagingURL) else { return }
        try? fileSystem.removeItem(at: stagingURL)
    }

    // MARK: - Coding

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
