import CellarTestSupport
import Foundation
import Synchronization

@testable import BrewClient
@testable import BrewProcess

/// A scripted services payload source that counts what it was asked and can be
/// held open, so a test can decide which acquisition answers first.
///
/// `FakeInstalledPayloadSource`'s shape, over services. It duplicates that type
/// rather than generalising it: the two answer different error types under
/// typed `throws`, and a shared generic would have to erase them.
final class FakeServicesPayloadSource: ServicesPayloadSourcing, Sendable {
    /// What one acquisition resolves to.
    enum Answer: Sendable {
        case payload(String)
        case failure(ServicesError)

        /// A list holding exactly the named services, all started.
        static func services(_ names: [String], status: String = "started") -> Answer {
            .payload(
                ServicesFixture.list(
                    names.map { ServicesFixture.record(name: $0, status: status) }
                )
            )
        }
    }

    private struct State {
        var answers: [Answer]
        var installations: [BrewInstallation] = []
        var isOpen: Bool
        var openCalls: Set<Int> = []
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - answers: one per acquisition; the last one repeats.
    ///   - gated: when true, each acquisition blocks until it is released.
    init(_ answers: [Answer], gated: Bool = false) {
        state = Mutex(State(answers: answers, isOpen: !gated))
    }

    var callCount: Int { state.withLock { $0.installations.count } }
    var installations: [BrewInstallation] { state.withLock { $0.installations } }

    /// Lets every held acquisition finish.
    func release() {
        state.withLock { $0.isOpen = true }
    }

    /// Lets only the `index`-th acquisition (0-based) finish.
    func release(call index: Int) {
        state.withLock { _ = $0.openCalls.insert(index) }
    }

    func waitForCalls(atLeast count: Int) async {
        await TestPoll.until(self.callCount >= count)
    }

    func payload(
        using installation: BrewInstallation
    ) async throws(ServicesError) -> Data {
        let (index, answer) = state.withLock { state -> (Int, Answer) in
            let index = state.installations.count
            state.installations.append(installation)
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

/// A scripted detail source, keyed by the service it was asked about.
///
/// Holdable for the same reason `FakeServicesPayloadSource` is: a probe that
/// answers instantly can never be superseded, so the guard that discards a
/// stale answer — or a stale *failure* — would have nothing to discard.
final class FakeServiceDetailSource: ServiceDetailPayloadSourcing, Sendable {
    private struct State {
        var payloads: [String: String]
        var requested: [String] = []
        var isOpen: Bool
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - payloads: what each named service answers; an unlisted name is
    ///     refused as a malformed payload.
    ///   - gated: when true, each probe blocks until it is released.
    init(
        _ payloads: [String: String] = ["atuin": ServicesFixture.infoWithIdenticalLogPaths],
        gated: Bool = false
    ) {
        state = Mutex(State(payloads: payloads, isOpen: !gated))
    }

    /// Every service name asked about, in order.
    var requested: [String] { state.withLock { $0.requested } }
    var callCount: Int { state.withLock { $0.requested.count } }

    /// Lets every held probe finish.
    func release() {
        state.withLock { $0.isOpen = true }
    }

    func waitForCalls(atLeast count: Int) async {
        await TestPoll.until(self.callCount >= count)
    }

    func payload(
        using installation: BrewInstallation,
        naming target: ServiceTarget
    ) async throws(ServicesError) -> Data {
        let payload = state.withLock { state -> String? in
            state.requested.append(target.name)
            return state.payloads[target.name]
        }

        await TestPoll.until(self.isOpen)

        guard let payload else { throw .malformedPayload }
        return Data(payload.utf8)
    }

    private var isOpen: Bool { state.withLock { $0.isOpen } }
}
