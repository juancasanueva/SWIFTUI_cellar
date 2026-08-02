import Foundation
import Synchronization

/// A wall-clock seam whose `now` a test moves by hand.
///
/// Separate from `TestClock` (now in `CellarTestSupport`, design D9) on purpose:
/// the refresh loop sleeps on a monotonic clock but decides staleness from
/// wall-clock time, and D5 requires proving those two can diverge (laptop asleep
/// for 30 h while the monotonic clock is paused).
/// Conformance to `CatalogTimeSource` is declared next to the sync-engine fakes.
final class FakeTimeSource: Sendable {
    private let state: Mutex<Date>

    init(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        state = Mutex(now)
    }

    var now: Date { state.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        state.withLock { $0 += interval }
    }

    func set(_ date: Date) {
        state.withLock { $0 = date }
    }
}
