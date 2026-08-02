import CellarTestSupport
import Synchronization

/// A one-shot barrier a test opens by hand.
///
/// The single-flight scenarios all read "a source that does not answer until it
/// is released": callers have to be provably *inside* the work before the test
/// decides anything, and a sleep long enough to make that likely is both slow
/// and still a race. Waiters park on a continuation instead, so `open()` is the
/// only thing that can let them through.
final class Gate: Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    /// How many callers are parked right now.
    var waiterCount: Int { state.withLock { $0.waiters.count } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let alreadyOpen = state.withLock { state -> Bool in
                guard !state.isOpen else { return true }
                state.waiters.append(continuation)
                return false
            }
            if alreadyOpen { continuation.resume() }
        }
    }

    /// Lets everyone through, now and afterwards.
    func open() {
        let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            let parked = state.waiters
            state.waiters = []
            return parked
        }
        // Resumed outside the lock: a continuation can run arbitrary code.
        for waiter in waiting { waiter.resume() }
    }

    func waitForWaiters(atLeast count: Int) async {
        await TestPoll.until(self.waiterCount >= count)
    }
}
