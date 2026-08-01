import Foundation
import Synchronization

@testable import BrewProcess

/// A scripted file system: paths are either absent, present but not executable,
/// executable, or a symlink to another scripted path.
final class FakeExecutableProbe: ExecutableProbing, Sendable {
    enum Entry: Sendable {
        /// A regular file with the execute bit set.
        case executable
        /// Present, but not runnable (wrong mode, or a directory).
        case notExecutable
        /// A symlink pointing at another path in this probe.
        case symlink(to: String)
    }

    private struct State {
        var entries: [String: Entry]
        var probedPaths: [String] = []
    }

    private let state: Mutex<State>

    init(entries: [String: Entry]) {
        self.state = Mutex(State(entries: entries))
    }

    /// Paths whose executability was checked, in order.
    var probedPaths: [String] { state.withLock { $0.probedPaths } }

    func exists(at url: URL) -> Bool {
        state.withLock { $0.entries[url.path] != nil }
    }

    func isExecutableRegularFile(at url: URL) -> Bool {
        state.withLock { state in
            state.probedPaths.append(url.path)
            if case .executable = state.entries[url.path] { return true }
            return false
        }
    }

    func resolvingSymlinks(at url: URL) -> URL {
        state.withLock { state in
            guard case .symlink(let target) = state.entries[url.path] else { return url }
            return URL(fileURLWithPath: target)
        }
    }
}
