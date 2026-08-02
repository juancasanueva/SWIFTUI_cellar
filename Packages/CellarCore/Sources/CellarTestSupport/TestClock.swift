import Synchronization

/// A manually advanced `Clock` so time-dependent tests never sleep on the wall
/// clock.
///
/// `sleep(until:)` suspends until `advance(by:)` moves `now` past the deadline,
/// which makes debounce windows and grace periods instantaneous and
/// deterministic.
///
/// This is the single copy (design D9). It previously existed three times —
/// once per test target — because separate test targets cannot share code and
/// the `CellarTestSupport` extraction (M2-0 D5) was deferred twice. The target
/// imports only `Synchronization`, so it needs no dependencies and no test
/// target gains an edge by depending on it.
public final class TestClock: Clock, Sendable {
    public struct Instant: InstantProtocol {
        public var offset: Duration

        public init(offset: Duration) {
            self.offset = offset
        }

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
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

    public init() {}

    public var now: Instant { state.withLock { $0.now } }
    public var minimumResolution: Duration { .zero }

    /// How many tasks are currently suspended in `sleep(until:)`.
    public var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
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
    public func advance(by duration: Duration) async {
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
    public func waitForSleepers(atLeast count: Int = 1) async {
        await TestPoll.until(sleeperCount >= count)
    }
}
