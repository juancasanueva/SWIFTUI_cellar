import Foundation
import Synchronization

@testable import Catalog

/// A `CatalogSource` whose answers are scripted per resource, recording every
/// request and the validators it carried.
///
/// The transport is the one dependency the sync engine must never reach around,
/// so this fake doubles as the assertion that it did not: a test that expects no
/// network sees an empty `requests` list, and there is no real `URLSession`
/// anywhere in the suite to accidentally succeed.
final class FakeCatalogSource: CatalogSource, Sendable {
    enum Scripted: Sendable {
        case notModified
        case payload(Data, validators: ConditionalValidators = ConditionalValidators())
        case failure(CatalogSyncError)
    }

    struct Request: Sendable, Equatable {
        let resource: CatalogResource
        let validators: ConditionalValidators?
    }

    private struct State {
        var scripts: [CatalogResource: [Scripted]] = [:]
        var requests: [Request] = []
        var deliveredPayloads = 0
        var onFetch: (@Sendable () async -> Void)?
    }

    private let state: Mutex<State> = Mutex(State())

    init() {}

    /// Consumed in order; the last entry repeats once the script runs out.
    func script(_ outcomes: [Scripted], for resource: CatalogResource) {
        state.withLock { $0.scripts[resource] = outcomes }
    }

    func script(_ outcome: Scripted, for resource: CatalogResource) {
        script([outcome], for: resource)
    }

    /// Runs before each answer — the seam a cancellation test needs.
    func onFetch(_ body: @escaping @Sendable () async -> Void) {
        state.withLock { $0.onFetch = body }
    }

    var requests: [Request] { state.withLock { $0.requests } }

    func requests(for resource: CatalogResource) -> [Request] {
        state.withLock { $0.requests.filter { $0.resource == resource } }
    }

    /// How many times a body actually crossed the seam. A revalidated resource
    /// must not increment this.
    var deliveredPayloadCount: Int { state.withLock { $0.deliveredPayloads } }

    func fetch(
        _ resource: CatalogResource,
        validators: ConditionalValidators?,
        into directory: URL
    ) async throws -> CatalogFetchOutcome {
        let hook = state.withLock { state -> (@Sendable () async -> Void)? in
            state.requests.append(Request(resource: resource, validators: validators))
            return state.onFetch
        }
        await hook?()
        try Task.checkCancellation()

        let outcome = state.withLock { state -> Scripted in
            guard var script = state.scripts[resource], !script.isEmpty else {
                return .failure(.offline)
            }
            let next = script.removeFirst()
            // The last entry sticks, so "503, 503, then success forever" is one
            // three-element script rather than a guessed repeat count.
            state.scripts[resource] = script.isEmpty ? [next] : script
            return next
        }

        switch outcome {
        case .notModified:
            return .notModified
        case .failure(let error):
            throw error
        case .payload(let data, let validators):
            let url = directory.appendingPathComponent("\(resource.rawValue).json")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
            state.withLock { $0.deliveredPayloads += 1 }
            return .downloaded(
                FetchedPayload(fileURL: url, validators: validators, byteCount: data.count)
            )
        }
    }
}

extension FakeTimeSource: CatalogTimeSource {}
