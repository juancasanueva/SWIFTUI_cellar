import Foundation
import Synchronization

@testable import BrewClient

/// A change source the test drives by hand.
///
/// The signal carries nothing, exactly like the real one: the coordinator's job
/// is to re-snapshot, never to interpret what changed (design D8).
final class FakeInstalledChangeObserver: InstalledChangeObserving, Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let emitted = Mutex(0)
    private let requested = Mutex(0)

    init() {
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    /// How many signals this observer has produced.
    var emittedCount: Int { emitted.withLock { $0 } }
    var changesCallCount: Int { requested.withLock { $0 } }

    /// Emits `count` change signals.
    func emit(_ count: Int = 1) {
        for _ in 0..<count {
            emitted.withLock { $0 += 1 }
            continuation.yield()
        }
    }

    func finish() {
        continuation.finish()
    }

    func changes() -> AsyncStream<Void> {
        requested.withLock { $0 += 1 }
        return stream
    }
}
