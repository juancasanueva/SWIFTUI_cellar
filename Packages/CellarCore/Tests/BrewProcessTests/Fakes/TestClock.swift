import Synchronization

/// A manually advanced `Clock` so cancellation-escalation tests never sleep on
/// the wall clock.
///
/// `sleep(until:)` suspends until `advance(by:)` moves `now` past the deadline,
/// which makes grace periods instantaneous and deterministic.
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

/// Bounded cooperative polling shared by the fakes.
///
/// Yields until `condition` holds or a generous wall-clock deadline passes, so
/// a broken expectation fails on its assertion instead of hanging the suite.
enum TestPoll {
    static func until(
        timeout: Duration = .seconds(5),
        _ condition: @autoclosure () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
    }
}
