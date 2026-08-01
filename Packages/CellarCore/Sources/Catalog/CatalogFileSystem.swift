import Foundation

/// The file-system operations the catalog needs, and nothing more.
///
/// A seam rather than direct `FileManager` calls because the two properties
/// persistence must guarantee — the swap is atomic, and the sidecar lands after
/// the snapshot — are statements about failure and ordering that a real disk
/// will not reproduce on request.
public protocol CatalogFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func contentsMappedIfSafe(of url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    /// Replaces `destination` with `staged` in one step, creating `destination`
    /// when it does not exist yet.
    func replaceItem(at destination: URL, withItemAt staged: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}

/// `FileManager`, with the atomic-replace fallback the first sync needs.
public struct DefaultCatalogFileSystem: CatalogFileSystem {
    public init() {}

    private var manager: FileManager { FileManager.default }

    public func createDirectory(at url: URL) throws {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func fileExists(at url: URL) -> Bool {
        manager.fileExists(atPath: url.path)
    }

    public func contentsMappedIfSafe(of url: URL) throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func replaceItem(at destination: URL, withItemAt staged: URL) throws {
        // `replaceItemAt` needs something to replace. On a first sync there is
        // nothing there yet, and a move is already atomic within a volume.
        guard fileExists(at: destination) else {
            try manager.moveItem(at: staged, to: destination)
            return
        }
        _ = try manager.replaceItemAt(destination, withItemAt: staged)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try manager.moveItem(at: source, to: destination)
    }

    public func removeItem(at url: URL) throws {
        try manager.removeItem(at: url)
    }
}
