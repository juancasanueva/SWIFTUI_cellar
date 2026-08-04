import CellarTestSupport
import Foundation
import Synchronization
import Testing

@testable import BrewClient
@testable import BrewProcess

@MainActor
@Suite("Tap store freshness", .timeLimit(.minutes(1)))
struct TapStoreTests {
    @Test("A failed refresh retains the last good snapshot")
    func failureRetainsLastGood() async {
        let source = FakeTapPayloadSource([
            .payload("[{\"name\":\"acme/tools\",\"repo\":\"tools\"}]"),
            .failure(.commandFailed(status: 1, message: "busy"))
        ])
        let store = TapStore(source: source)

        await store.refresh(using: TestInstallation.appleSilicon)
        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(store.inventory.taps.map(\.name) == ["acme/tools"])
        #expect(store.state == .failed(.commandFailed(status: 1, message: "busy")))
        #expect(source.callCount == 2)
    }

    @Test("Identical overlapping requests share one acquisition and later work is fresh")
    func overlapIsSingleFlight() async {
        let source = FakeTapPayloadSource([
            .payload("[{\"name\":\"acme/tools\",\"repo\":\"tools\"}]"),
            .payload("[{\"name\":\"other/home\",\"repo\":\"home\"}]")
        ], gated: true)
        let store = TapStore(source: source)
        let first = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        let joiner = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)
        source.release(call: 0)
        await first.value
        await joiner.value
        #expect(source.callCount == 1)

        let later = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 2)
        source.release(call: 1)
        await later.value
        #expect(source.callCount == 2)
        #expect(store.inventory.taps.map(\.name) == ["other/home"])
    }

    @Test("Invalidation starts new work and an older late answer cannot replace it")
    func newerWorkWins() async {
        let source = FakeTapPayloadSource([
            .payload("[{\"name\":\"old/tools\",\"repo\":\"tools\"}]"),
            .payload("[{\"name\":\"new/tools\",\"repo\":\"tools\"}]")
        ], gated: true)
        let store = TapStore(source: source)
        let old = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)
        store.invalidate()
        let new = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 2)

        source.release(call: 1)
        await new.value
        source.release(call: 0)
        await old.value

        #expect(source.callCount == 2)
        #expect(store.inventory.taps.map(\.name) == ["new/tools"])
    }
}

private final class FakeTapPayloadSource: TapPayloadSourcing, Sendable {
    enum Answer: Sendable {
        case payload(String)
        case failure(TapInventoryError)
    }

    private struct State {
        var answers: [Answer]
        var calls = 0
        var isOpen: Bool
        var openCalls: Set<Int> = []
    }

    private let state: Mutex<State>

    init(_ answers: [Answer], gated: Bool = false) {
        state = Mutex(State(answers: answers, isOpen: !gated))
    }

    var callCount: Int { state.withLock(\.calls) }

    func release(call index: Int) {
        state.withLock { _ = $0.openCalls.insert(index) }
    }

    func waitForCalls(atLeast count: Int) async {
        await TestPoll.until(self.callCount >= count)
    }

    func payload(using _: BrewInstallation) async throws(TapInventoryError) -> Data {
        let (index, answer) = state.withLock { state -> (Int, Answer) in
            let index = state.calls
            state.calls += 1
            return (index, state.answers[min(index, state.answers.count - 1)])
        }
        await TestPoll.until(self.isOpen(call: index))
        switch answer {
        case .payload(let text): return Data(text.utf8)
        case .failure(let error): throw error
        }
    }

    private func isOpen(call index: Int) -> Bool {
        state.withLock { $0.isOpen || $0.openCalls.contains(index) }
    }
}
