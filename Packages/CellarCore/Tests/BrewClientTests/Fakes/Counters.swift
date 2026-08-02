import Synchronization

/// A counter several tasks can bump.
final class Counter: Sendable {
    private let storage = Mutex(0)

    var value: Int { storage.withLock { $0 } }

    func increment() { storage.withLock { $0 += 1 } }
}

/// A one-way switch, so a ticker task knows when to stop.
final class Flag: Sendable {
    private let storage = Mutex(false)

    var isSet: Bool { storage.withLock { $0 } }

    func set() { storage.withLock { $0 = true } }
}
