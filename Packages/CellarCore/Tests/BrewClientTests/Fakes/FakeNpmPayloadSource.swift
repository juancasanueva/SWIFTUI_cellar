import Foundation
import Synchronization

@testable import BrewClient
@testable import BrewProcess

/// A scripted npm payload source that counts what it was asked.
final class FakeNpmPayloadSource: NpmPayloadSourcing, Sendable {
    enum Answer: Sendable {
        case payload(String)
        case failure(NpmInventoryError)

        /// A listing holding exactly these `name: version` pairs.
        static func globals(_ pairs: [(String, String)]) -> Answer {
            let entries = pairs
                .map { #""\#($0.0)":{"version":"\#($0.1)","overridden":false}"# }
                .joined(separator: ",")
            return .payload(#"{"name":"lib","dependencies":{\#(entries)}}"#)
        }

        /// A report marking each name outdated toward the given version.
        static func report(_ pairs: [(String, current: String, latest: String)]) -> Answer {
            let entries = pairs
                .map {
                    #""\#($0.0)":{"current":"\#($0.current)","wanted":"\#($0.latest)","#
                        + #""latest":"\#($0.latest)"}"#
                }
                .joined(separator: ",")
            return .payload("{\(entries)}")
        }
    }

    private struct State {
        var listings: [Answer]
        var reports: [Answer]
        var listingCalls: [NpmEnvironment] = []
        var reportCalls: [NpmEnvironment] = []
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - listings: one per `installed(using:)`; the last one repeats.
    ///   - reports: one per `outdated(using:)`; the last one repeats.
    init(listings: [Answer] = [.globals([])], reports: [Answer] = [.payload("{}")]) {
        state = Mutex(State(listings: listings, reports: reports))
    }

    var listingCount: Int { state.withLock { $0.listingCalls.count } }
    var reportCount: Int { state.withLock { $0.reportCalls.count } }
    var environments: [NpmEnvironment] {
        state.withLock { $0.listingCalls + $0.reportCalls }
    }

    func installed(using environment: NpmEnvironment) async throws(NpmInventoryError) -> Data {
        let answer = state.withLock { state -> Answer in
            state.listingCalls.append(environment)
            return state.listings[min(state.listingCalls.count - 1, state.listings.count - 1)]
        }
        return try Self.resolve(answer)
    }

    func outdated(using environment: NpmEnvironment) async throws(NpmInventoryError) -> Data {
        let answer = state.withLock { state -> Answer in
            state.reportCalls.append(environment)
            return state.reports[min(state.reportCalls.count - 1, state.reports.count - 1)]
        }
        return try Self.resolve(answer)
    }

    private static func resolve(_ answer: Answer) throws(NpmInventoryError) -> Data {
        switch answer {
        case .payload(let text): Data(text.utf8)
        case .failure(let error): throw error
        }
    }
}

/// A clock that answers whatever the test set, so "when was this checked" is a
/// value rather than a moment.
final class FixedNpmClock: NpmClock, Sendable {
    private let instant: Mutex<Date>

    init(_ instant: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.instant = Mutex(instant)
    }

    func advance(by interval: TimeInterval) {
        instant.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    func now() -> Date { instant.withLock { $0 } }
}
