import CellarTestSupport
import Foundation
import Synchronization

@testable import BrewClient
@testable import BrewProcess

/// A scripted `TrustGrantSourcing`, gated exactly like `TapStoreTests`' tap
/// double so overlap and coalescing are observable rather than inferred.
final class FakeTrustGrantPayloadSource: TrustGrantSourcing, Sendable {
    enum Answer: Sendable {
        case payload(String)
        case failure(TrustGrantError)
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

    func releaseAll() {
        state.withLock { $0.isOpen = true }
    }

    func waitForCalls(atLeast count: Int) async {
        await TestPoll.until(self.callCount >= count)
    }

    func payload(using _: BrewInstallation) async throws(TrustGrantError) -> Data {
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

/// The same double for the **tap** read, so a coordinator test can hold one read
/// open while the other runs.
///
/// Named apart from `TapStoreTests`' file-private `FakeTapPayloadSource` on
/// purpose: two doubles with one name, one of them invisible, is the kind of
/// thing that reads as a mistake later.
final class GatedTapPayloadSource: TapPayloadSourcing, Sendable {
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
