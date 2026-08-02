import Foundation
import Synchronization

@testable import Catalog

/// An in-memory `CatalogFileSystem` that records what happened and can be told
/// to fail a specific path.
///
/// Persistence has exactly two properties worth proving — the swap is atomic and
/// the sidecar lands *after* the snapshot — and both are statements about
/// ordering and failure, which a real temp directory cannot make fail on demand.
final class FakeCatalogFileSystem: CatalogFileSystem, Sendable {
    enum Operation: Equatable {
        case createDirectory(String)
        case write(String)
        case replace(destination: String, staged: String)
        case move(source: String, destination: String)
        case remove(String)
    }

    private struct State {
        var files: [String: Data] = [:]
        var directories: Set<String> = []
        var operations: [Operation] = []
        var failingWrites: Set<String> = []
        var failingReplacements: Set<String> = []
    }

    private let state: Mutex<State> = Mutex(State())

    var operations: [Operation] { state.withLock { $0.operations } }

    /// Only the operations that mutate the two published files, in order — the
    /// staging churn is noise for an ordering assertion.
    var publishedPaths: [String] {
        state.withLock {
            $0.operations.compactMap { operation in
                switch operation {
                case .replace(let destination, _): destination
                case .move(_, let destination): destination
                default: nil
                }
            }
        }
        .map { ($0 as NSString).lastPathComponent }
    }

    /// Whether the staging directory was created or removed, in order.
    ///
    /// The one question the mark-and-drain single-flight rule turns on: a
    /// cancelled run's purge has to land before its successor stages anything,
    /// or the successor's download is deleted underneath it.
    enum StagingEvent: Equatable {
        case created
        case purged
    }

    func stagingLifecycle(at url: URL) -> [StagingEvent] {
        operations.compactMap { operation in
            switch operation {
            case .createDirectory(url.path): .created
            case .remove(url.path): .purged
            default: nil
            }
        }
    }

    func seed(_ data: Data, at url: URL) {
        state.withLock { $0.files[url.path] = data }
    }

    func contents(at url: URL) -> Data? {
        state.withLock { $0.files[url.path] }
    }

    func failWrites(to url: URL) {
        state.withLock { _ = $0.failingWrites.insert(url.path) }
    }

    func failReplacements(of url: URL) {
        state.withLock { _ = $0.failingReplacements.insert(url.path) }
    }

    // MARK: - CatalogFileSystem

    func createDirectory(at url: URL) throws {
        state.withLock {
            $0.operations.append(.createDirectory(url.path))
            $0.directories.insert(url.path)
        }
    }

    func fileExists(at url: URL) -> Bool {
        state.withLock { $0.files[url.path] != nil || $0.directories.contains(url.path) }
    }

    func contentsMappedIfSafe(of url: URL) throws -> Data {
        try state.withLock {
            guard let data = $0.files[url.path] else {
                throw CocoaError(.fileNoSuchFile)
            }
            return data
        }
    }

    func write(_ data: Data, to url: URL) throws {
        try state.withLock {
            $0.operations.append(.write(url.path))
            guard !$0.failingWrites.contains(url.path) else {
                throw CocoaError(.fileWriteUnknown)
            }
            $0.files[url.path] = data
        }
    }

    func replaceItem(at destination: URL, withItemAt staged: URL) throws {
        try state.withLock {
            $0.operations.append(.replace(destination: destination.path, staged: staged.path))
            guard !$0.failingReplacements.contains(destination.path) else {
                throw CocoaError(.fileWriteUnknown)
            }
            guard let data = $0.files[staged.path] else {
                throw CocoaError(.fileNoSuchFile)
            }
            $0.files[destination.path] = data
            $0.files[staged.path] = nil
        }
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try state.withLock {
            $0.operations.append(.move(source: source.path, destination: destination.path))
            guard let data = $0.files[source.path] else {
                throw CocoaError(.fileNoSuchFile)
            }
            $0.files[destination.path] = data
            $0.files[source.path] = nil
        }
    }

    func removeItem(at url: URL) throws {
        state.withLock {
            $0.operations.append(.remove(url.path))
            $0.files[url.path] = nil
            $0.directories.remove(url.path)
            for path in $0.files.keys where path.hasPrefix(url.path + "/") {
                $0.files[path] = nil
            }
        }
    }
}
