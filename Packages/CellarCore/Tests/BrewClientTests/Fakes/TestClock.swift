import Synchronization

/// A manually advanced `Clock` so debounce tests never sleep on the wall clock.
///
/// The **third** copy of this helper. `CellarTestSupport` (M2-0 D5) would have
/// held one shared copy, but that extraction was cut before it landed and this
/// change deliberately does not revive it: separate test targets cannot share
/// code without it, and reviving a deferred refactor inside a change this size
/// is how scope creep starts. The duplication is tracked, not accidental.
final class TestClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        var nextID = 0
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    /// How many tasks are currently suspended in `sleep(until:)`.
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let alreadyDue = state.withLock { state -> Bool in
                guard state.now < deadline else { return true }
                state.nextID += 1
                state.sleepers.append(
                    Sleeper(id: state.nextID, deadline: deadline, continuation: continuation)
                )
                return false
            }
            if alreadyDue { continuation.resume() }
        }
    }

    /// Moves time forward and resumes every sleeper whose deadline has passed.
    func advance(by duration: Duration) async {
        let due = state.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let reached = state.sleepers.filter { $0.deadline <= state.now }
            state.sleepers.removeAll { $0.deadline <= state.now }
            return reached
        }
        for sleeper in due { sleeper.continuation.resume() }
        await Task.yield()
    }

    /// Suspends until at least `count` tasks are waiting on this clock, so a
    /// test can advance time without racing the code that starts sleeping.
    func waitForSleepers(atLeast count: Int = 1) async {
        await TestPoll.until(sleeperCount >= count)
    }
}
