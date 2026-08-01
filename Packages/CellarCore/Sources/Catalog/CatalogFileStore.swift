import Foundation

/// Reads and writes the two files that make up the persisted catalog.
///
/// `catalog.json` is the snapshot; `catalog-state.json` is the sidecar that says
/// how fresh it is and which validators to replay. They are always published in
/// that order (design D3).
public struct CatalogFileStore: Sendable {
    public let directory: URL
    private let fileSystem: any CatalogFileSystem

    public init(directory: URL, fileSystem: any CatalogFileSystem = DefaultCatalogFileSystem()) {
        self.directory = directory
        self.fileSystem = fileSystem
    }

    public var snapshotURL: URL { directory.appendingPathComponent("catalog.json") }
    public var stateURL: URL { directory.appendingPathComponent("catalog-state.json") }
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
        guard schemaVersion(of: data) == CatalogSnapshot.currentSchemaVersion else { return nil }
        return try? decoder.decode(CatalogSnapshot.self, from: data)
    }

    public func loadState() throws -> CatalogState? {
        guard let data = try? fileSystem.contentsMappedIfSafe(of: stateURL) else { return nil }
        guard schemaVersion(of: data) == CatalogSnapshot.currentSchemaVersion else { return nil }
        return try? decoder.decode(CatalogState.self, from: data)
    }

    /// Reads only the version field, so a payload whose *other* fields this
    /// build cannot parse is still classified correctly.
    private func schemaVersion(of data: Data) -> Int? {
        struct VersionProbe: Decodable { let schemaVersion: Int }
        return (try? decoder.decode(VersionProbe.self, from: data))?.schemaVersion
    }

    // MARK: - Writing

    /// Publishes a snapshot and its sidecar, snapshot first.
    ///
    /// A crash between the two leaves a fresh catalog advertised with stale
    /// validators, which costs one redundant download. The reverse order would
    /// advertise a stale catalog as fresh, which serves wrong data (design D3).
    public func persist(_ snapshot: CatalogSnapshot, state: CatalogState) throws {
        do {
            try fileSystem.createDirectory(at: directory)
            try publish(try encoder.encode(snapshot), to: snapshotURL, stagedAs: "catalog.json.new")
            try publish(try encoder.encode(state), to: stateURL, stagedAs: "catalog-state.json.new")
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
