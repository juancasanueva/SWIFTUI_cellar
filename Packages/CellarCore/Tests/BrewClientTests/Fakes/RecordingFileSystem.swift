import Foundation
import Synchronization

@testable import Catalog

/// A `CatalogFileSystem` that records every call and touches no real disk.
///
/// **Per-instance**, with its own `Mutex`-guarded ledger. Deliberately not a
/// shared or static counter: `cellarTests/SecurityCompositionSupport.swift`'s
/// `CompositionRequestSpy` uses a static shape, and that shape produced slice
/// 3's false zero — a spy that asserts nothing while looking like it asserts
/// everything.
///
/// It exists so three claims can be made about the export that a real disk
/// would not reproduce on request: the temporary directory is removed on
/// success, on failure **and** on cancellation; a failed publication leaves the
/// pre-existing destination untouched; and no path the user chose ever reaches
/// a `brew` argv.
final class RecordingFileSystem: CatalogFileSystem, Sendable {
    enum Call: Sendable, Equatable {
        case createDirectory(URL)
        case fileExists(URL)
        case read(URL)
        case write(URL, byteCount: Int)
        case replaceItem(destination: URL, staged: URL)
        case moveItem(from: URL, to: URL)
        case removeItem(URL)
    }

    private struct State {
        var calls: [Call] = []
        var contents: [URL: Data] = [:]
        var readError: (any Error)?
        var writeError: (any Error)?
        /// Stands in for the bytes the **subprocess** wrote at a path this fake
        /// never saw created. The dump's document arrives on disk from `brew`,
        /// not through this seam, so a test that wants to observe the read has
        /// to be able to answer it without knowing the per-export UUID.
        var subprocessDocument: Data?
    }

    private let state = Mutex(State())

    init(contents: [URL: Data] = [:]) {
        state.withLock { $0.contents = contents }
    }

    var calls: [Call] { state.withLock { $0.calls } }
    var contents: [URL: Data] { state.withLock { $0.contents } }

    /// The bytes at `url`, or `nil` if nothing is there.
    func bytes(at url: URL) -> Data? { state.withLock { $0.contents[url] } }

    func seed(_ data: Data, at url: URL) { state.withLock { $0.contents[url] = data } }

    /// Answers any read of a path this fake has no record of, as the real disk
    /// would after `brew` wrote the dump there.
    func answerSubprocessWrite(with data: Data) {
        state.withLock { $0.subprocessDocument = data }
    }
    func failReads(with error: any Error) { state.withLock { $0.readError = error } }
    func failWrites(with error: any Error) { state.withLock { $0.writeError = error } }

    /// Whether anything under `url` still exists — the observable form of
    /// "the temporary directory was removed".
    func containsAnything(under url: URL) -> Bool {
        state.withLock { state in
            state.contents.keys.contains { $0.path.hasPrefix(url.path) }
        }
    }

    // MARK: - CatalogFileSystem

    func createDirectory(at url: URL) throws {
        state.withLock { $0.calls.append(.createDirectory(url)) }
    }

    func fileExists(at url: URL) -> Bool {
        state.withLock { state in
            state.calls.append(.fileExists(url))
            return state.contents[url] != nil
        }
    }

    func contentsMappedIfSafe(of url: URL) throws -> Data {
        let outcome = state.withLock { state -> Result<Data, any Error> in
            state.calls.append(.read(url))
            if let error = state.readError { return .failure(error) }
            guard let data = state.contents[url] ?? state.subprocessDocument else {
                return .failure(CocoaError(.fileNoSuchFile))
            }
            return .success(data)
        }
        return try outcome.get()
    }

    func write(_ data: Data, to url: URL) throws {
        let error = state.withLock { state -> (any Error)? in
            state.calls.append(.write(url, byteCount: data.count))
            if let error = state.writeError { return error }
            // Atomic by construction here: the assignment either happens or it
            // does not, so a failed write can never leave a partial file.
            state.contents[url] = data
            return nil
        }
        if let error { throw error }
    }

    func replaceItem(at destination: URL, withItemAt staged: URL) throws {
        state.withLock { state in
            state.calls.append(.replaceItem(destination: destination, staged: staged))
            state.contents[destination] = state.contents.removeValue(forKey: staged)
        }
    }

    func moveItem(at source: URL, to destination: URL) throws {
        state.withLock { state in
            state.calls.append(.moveItem(from: source, to: destination))
            state.contents[destination] = state.contents.removeValue(forKey: source)
        }
    }

    func removeItem(at url: URL) throws {
        state.withLock { state in
            state.calls.append(.removeItem(url))
            for key in state.contents.keys where key.path.hasPrefix(url.path) {
                state.contents.removeValue(forKey: key)
            }
        }
    }
}
