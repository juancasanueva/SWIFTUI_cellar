import Synchronization

/// An ordered log of labelled events several tasks can append to.
///
/// The ordering questions in this change — did main-actor work finish before
/// the index build, did the newer adoption install last — are all statements
/// about sequence, and a sequence is the only thing that can prove them.
final class Recorder: Sendable {
    private let entries = Mutex<[String]>([])

    var labels: [String] { entries.withLock { $0 } }

    func record(_ label: String) {
        entries.withLock { $0.append(label) }
    }

    func count(of label: String) -> Int {
        entries.withLock { $0.count { $0 == label } }
    }
}

/// A set-once flag several tasks can share.
///
/// `Mutex` is non-copyable, so it cannot be captured by more than one escaping
/// closure directly; a `Sendable` reference around it can.
final class Flag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool { value.withLock { $0 } }

    func set() { value.withLock { $0 = true } }
}

/// A counter several tasks can bump.
final class Counter: Sendable {
    private let state = Mutex(0)

    var value: Int { state.withLock { $0 } }

    func increment() {
        state.withLock { $0 += 1 }
    }
}
