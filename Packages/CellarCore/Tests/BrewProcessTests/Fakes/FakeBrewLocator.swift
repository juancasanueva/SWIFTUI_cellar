import Foundation
import Synchronization

@testable import BrewProcess

/// A scripted locator that can be held open, so tests can observe what happens
/// while a detection is still in flight.
final class FakeBrewLocator: BrewLocating, Sendable {
    private struct State {
        var results: [BrewDetectionState]
        var callCount = 0
        var configuredPaths: [URL?] = []
        var isGateOpen: Bool
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - results: one state per call; the last one repeats.
    ///   - gated: when true, `detect` blocks until `release()` is called.
    init(results: [BrewDetectionState], gated: Bool = false) {
        self.state = Mutex(State(results: results, isGateOpen: !gated))
    }

    var callCount: Int { state.withLock { $0.callCount } }
    var configuredPaths: [URL?] { state.withLock { $0.configuredPaths } }

    /// Lets a gated detection finish.
    func release() {
        state.withLock { $0.isGateOpen = true }
    }

    func waitForCalls(atLeast count: Int) async {
        await TestPoll.until(self.callCount >= count)
    }

    func detect(configuredPath: URL?) async -> BrewDetectionState {
        let result = state.withLock { state -> BrewDetectionState in
            state.configuredPaths.append(configuredPath)
            let index = min(state.callCount, state.results.count - 1)
            state.callCount += 1
            return state.results[index]
        }
        await TestPoll.until(self.state.withLock { $0.isGateOpen })
        return result
    }
}
