import CellarTestSupport
import Foundation
import Synchronization

@testable import BrewProcess

/// Records every `ProcessSpec` it is asked to launch and hands back scripted
/// `FakeProcess` instances instead of spawning anything.
final class FakeProcessLauncher: ProcessLaunching, Sendable {
    private struct State {
        var specs: [ProcessSpec] = []
        var queued: [FakeProcess] = []
        var launched: [FakeProcess] = []
        var launchError: (any Error)?
    }

    private let state = Mutex(State())
    private let defaultBehavior: FakeProcess.SignalBehavior
    private let clock: TestClock?

    init(behavior: FakeProcess.SignalBehavior = .manual, clock: TestClock? = nil) {
        self.defaultBehavior = behavior
        self.clock = clock
    }

    /// Scripts the next process handed out by `launch(_:)`.
    func enqueue(_ process: FakeProcess) {
        state.withLock { $0.queued.append(process) }
    }

    /// Makes the next `launch(_:)` throw instead of returning a process.
    func failLaunch(with error: any Error) {
        state.withLock { $0.launchError = error }
    }

    /// Every spec passed to `launch(_:)`, in order.
    var recordedSpecs: [ProcessSpec] { state.withLock { $0.specs } }

    /// Every process actually handed out, in launch order.
    var launchedProcesses: [FakeProcess] { state.withLock { $0.launched } }

    var launchCount: Int { state.withLock { $0.launched.count } }

    /// Suspends until at least `count` launches have happened.
    func waitForLaunches(atLeast count: Int) async {
        await TestPoll.until(self.launchCount >= count)
    }

    /// Suspends until `count` launches have happened, then keeps yielding
    /// briefly to give any extra (unwanted) launch a chance to appear.
    func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess {
        let outcome = state.withLock { state -> Result<FakeProcess, any Error> in
            state.specs.append(spec)
            if let error = state.launchError {
                return .failure(error)
            }
            let process = state.queued.isEmpty
                ? FakeProcess(behavior: defaultBehavior, clock: clock)
                : state.queued.removeFirst()
            state.launched.append(process)
            return .success(process)
        }
        return try outcome.get()
    }
}
