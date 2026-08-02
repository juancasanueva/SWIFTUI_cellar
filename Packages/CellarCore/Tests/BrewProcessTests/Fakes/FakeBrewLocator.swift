import Foundation
import Synchronization

@testable import BrewProcess

/// A scripted locator that can be held open, so tests can observe what happens
/// while a detection is still in flight.
final class FakeBrewLocator: BrewLocating, Sendable {
    private struct State {
        var results: [BrewDetectionState]
        /// A script keyed by the question rather than by the call index, for the
        /// tests where *which path was asked about* is the thing under test.
        var resultsByPath: [URL?: BrewDetectionState] = [:]
        var callCount = 0
        var configuredPaths: [URL?] = []
        var isGateOpen: Bool
        /// Paths released individually, so a test can decide which evaluation
        /// answers first.
        var openPaths: Set<URL?> = []
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - results: one state per call; the last one repeats.
    ///   - gated: when true, `detect` blocks until `release()` is called.
    init(results: [BrewDetectionState], gated: Bool = false) {
        self.state = Mutex(State(results: results, isGateOpen: !gated))
    }

    /// - Parameters:
    ///   - resultsByPath: the answer each configured path resolves to. An
    ///     unscripted path resolves `.absent`.
    ///   - gated: when true, `detect` blocks until the path is released.
    init(resultsByPath: [URL?: BrewDetectionState], gated: Bool = false) {
        self.state = Mutex(
            State(results: [], resultsByPath: resultsByPath, isGateOpen: !gated)
        )
    }

    var callCount: Int { state.withLock { $0.callCount } }
    var configuredPaths: [URL?] { state.withLock { $0.configuredPaths } }

    /// How many times this exact question was asked.
    func callCount(for path: URL?) -> Int {
        state.withLock { $0.configuredPaths.count { $0 == path } }
    }

    /// Lets every gated detection finish.
    func release() {
        state.withLock { $0.isGateOpen = true }
    }

    /// Lets only the detections asking about `path` finish.
    func release(_ path: URL?) {
        state.withLock { _ = $0.openPaths.insert(path) }
    }

    func waitForCalls(atLeast count: Int) async {
        await TestPoll.until(self.callCount >= count)
    }

    func detect(configuredPath: URL?) async -> BrewDetectionState {
        let result = state.withLock { state -> BrewDetectionState in
            state.configuredPaths.append(configuredPath)
            state.callCount += 1
            if !state.resultsByPath.isEmpty {
                return state.resultsByPath[configuredPath] ?? .absent
            }
            return state.results[min(state.callCount - 1, state.results.count - 1)]
        }
        await TestPoll.until(self.isOpen(for: configuredPath))
        return result
    }

    private func isOpen(for path: URL?) -> Bool {
        state.withLock { $0.isGateOpen || $0.openPaths.contains(path) }
    }
}
