import Foundation
import Synchronization

@testable import BrewClient
@testable import BrewProcess

/// A scripted payload source that counts what it was asked and can be held
/// open, so a test can decide which acquisition answers first.
final class FakeInstalledPayloadSource: InstalledPayloadSourcing, Sendable {
    /// What one acquisition resolves to.
    enum Answer: Sendable {
        case payload(String)
        case failure(InstalledInventoryError)

        /// A snapshot holding exactly the named formulae, on request.
        static func formulae(_ names: [String], version: String = "1.0.0") -> Answer {
            let records = names.map {
                """
                {"name":"\($0)","tap":"homebrew/core","versions":{"stable":"\(version)"},\
                "installed":[{"version":"\(version)","time":1700000000,\
                "installed_on_request":true}],"outdated":false}
                """
            }
            return .payload("{\"formulae\":[\(records.joined(separator: ","))],\"casks\":[]}")
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
    ) async throws(InstalledInventoryError) -> Data {
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
