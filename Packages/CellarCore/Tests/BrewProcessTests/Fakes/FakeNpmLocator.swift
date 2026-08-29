import CellarTestSupport
import Foundation
import Synchronization

@testable import BrewProcess

/// A scripted npm locator that can be held open, so a test can observe what
/// happens while a detection is still in flight.
///
/// Its own type rather than a generic over `FakeBrewLocator`: the point of this
/// change is that brew's detection vocabulary is untouched, and a shared fake
/// parameterised over both states would be the first place that stops being
/// true.
final class FakeNpmLocator: NpmLocating, Sendable {
    private struct State {
        var results: [NpmDetectionState]
        var resultsByPath: [URL?: NpmDetectionState] = [:]
        var callCount = 0
        var configuredPaths: [URL?] = []
        var isGateOpen: Bool
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - results: one state per call; the last one repeats.
    ///   - gated: when true, `detect` blocks until `release()` is called.
    init(results: [NpmDetectionState], gated: Bool = false) {
        self.state = Mutex(State(results: results, isGateOpen: !gated))
    }

    init(resultsByPath: [URL?: NpmDetectionState], gated: Bool = false) {
        self.state = Mutex(State(results: [], resultsByPath: resultsByPath, isGateOpen: !gated))
    }

    var callCount: Int { state.withLock { $0.callCount } }
    var configuredPaths: [URL?] { state.withLock { $0.configuredPaths } }

    func release() {
        state.withLock { $0.isGateOpen = true }
    }

    func waitForCalls(atLeast count: Int) async {
        await TestPoll.until(self.callCount >= count)
    }

    func detect(configuredPath: URL?) async -> NpmDetectionState {
        let result = state.withLock { state -> NpmDetectionState in
            state.configuredPaths.append(configuredPath)
            state.callCount += 1
            if state.resultsByPath.isEmpty == false {
                return state.resultsByPath[configuredPath] ?? .absent
            }
            return state.results[min(state.callCount - 1, state.results.count - 1)]
        }
        await TestPoll.until(self.isOpen)
        return result
    }

    private var isOpen: Bool { state.withLock { $0.isGateOpen } }
}
