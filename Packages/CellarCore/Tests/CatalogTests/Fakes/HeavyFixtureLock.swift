import Testing

/// Serializes the tests that materialise a realistically sized catalog.
///
/// `CatalogMemoryTests` asserts a budget on *process* footprint, which only
/// means anything while nothing else in the process is allocating tens of
/// megabytes. Swift Testing runs suites in parallel, and the catalog-sized
/// fixtures live in four different suites, so without this they measure each
/// other: the decode budget reads 40–80 MB of somebody else's snapshot.
///
/// `.serialized` cannot express this — it orders a suite's own tests, not two
/// suites against each other — so the heavy tests take turns explicitly.
/// Applied as `.heavyFixture` so a test body keeps its own shape — the tests
/// wearing this are the ones that build a 15,000-record catalog or a 40 MB
/// payload.
struct HeavyFixtureTrait: TestTrait, SuiteTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await HeavyFixtureLock.exclusive { try await function() }
    }
}

extension Trait where Self == HeavyFixtureTrait {
    static var heavyFixture: Self { HeavyFixtureTrait() }
}

actor HeavyFixtureLock {
    private static let shared = HeavyFixtureLock()

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Runs `body` with no other heavy fixture resident.
    static func exclusive<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        await shared.acquire()
        do {
            let value = try await body()
            await shared.release()
            return value
        } catch {
            await shared.release()
            throw error
        }
    }

    private func acquire() async {
        while isHeld {
            await withCheckedContinuation { waiters.append($0) }
        }
        isHeld = true
    }

    private func release() {
        isHeld = false
        let resumed = waiters
        waiters = []
        // Resumed outside any further mutation: a waiter re-checks `isHeld`.
        for waiter in resumed { waiter.resume() }
    }
}
