import BrewProcess
import Foundation
import Observation

public enum TrustGrantLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case brewAbsent(InstalledAbsence)
    case failed(TrustGrantError)
}

/// Holds the per-package trust report, with the same discipline `TapStore`
/// already proves (package-trust PT2 :107-112).
///
/// Cloned member-for-member on purpose. A second read that did not coalesce, did
/// not keep its last good answer, and adopted whichever answer happened to land
/// last would be a worse citizen than the store beside it — and every one of
/// those three properties is a bug that only appears under load.
@MainActor
@Observable
public final class TrustGrantStore {
    /// What Homebrew last reported. `unreported` until it answers once.
    public private(set) var grants: TrustGrantState = .unreported
    /// The read's own state, kept for parity with `TapStore` and for tests. No
    /// view reads it: the surfaces are driven by `grants` alone, because a
    /// failing grant read is not something to tell the user about — it is
    /// something to claim nothing on the strength of.
    public private(set) var state: TrustGrantLoadState = .idle

    @ObservationIgnored private let source: any TrustGrantSourcing

    private struct InFlightRefresh {
        let token: Int
        let request: URL
        let mark: Int
        let task: Task<Result<TrustGrantLedger, TrustGrantError>, Never>
    }

    @ObservationIgnored private var inFlight: InFlightRefresh?
    @ObservationIgnored private var nextToken = 0
    @ObservationIgnored private var installedSequence = 0
    @ObservationIgnored private var invalidationCount = 0

    public init(source: any TrustGrantSourcing = BrewTrustGrantPayloadSource()) {
        self.source = source
    }

    public func invalidate() {
        invalidationCount += 1
    }

    public func refresh(for detection: BrewDetectionState) async {
        switch detection {
        case .detected(let installation): await refresh(using: installation)
        case .absent: clear(to: .notInstalled(.standard))
        case .invalid(let url, let reason): clear(to: .configuredPathRejected(url, reason))
        case .configuredPathMissing(let url): clear(to: .configuredPathMissing(url))
        }
    }

    public func refresh(using installation: BrewInstallation?) async {
        guard let installation else {
            clear(to: .notInstalled(.standard))
            return
        }
        let request = installation.executableURL
        let outcome: Result<TrustGrantLedger, TrustGrantError>
        let token: Int

        if let current = inFlight,
           current.request == request,
           current.mark >= invalidationCount {
            token = current.token
            outcome = await current.task.value
        } else {
            nextToken += 1
            token = nextToken
            state = .loading
            let acquisition = Task<Result<TrustGrantLedger, TrustGrantError>, Never> {
                [source, weak self] in
                defer { self?.vacate(token) }
                do {
                    let payload = try await source.payload(using: installation)
                    return .success(try await TrustGrantDecoder.decode(payload))
                } catch let error as TrustGrantError {
                    return .failure(error)
                } catch {
                    return .failure(.malformedJSON)
                }
            }
            inFlight = InFlightRefresh(
                token: token,
                request: request,
                mark: invalidationCount,
                task: acquisition
            )
            outcome = await acquisition.value
        }
        adopt(outcome, token: token)
    }

    private func adopt(_ outcome: Result<TrustGrantLedger, TrustGrantError>, token: Int) {
        guard token > installedSequence else { return }
        installedSequence = token
        // The last good report survives a failure rather than being replaced by
        // an empty one (PT2 :141-147). On a machine that never had one, the last
        // good value is `unreported`, which is the honest answer.
        grants = .settled(outcome, keeping: grants)
        switch outcome {
        case .success: state = .loaded
        case .failure(let error): state = .failed(error)
        }
    }

    private func clear(to absence: InstalledAbsence) {
        inFlight?.task.cancel()
        inFlight = nil
        nextToken += 1
        installedSequence = nextToken
        // A brew that is gone reports nothing. Keeping the last good ledger here
        // would attribute grants to a Homebrew that is not there.
        grants = .unreported
        state = .brewAbsent(absence)
    }

    private func vacate(_ token: Int) {
        guard inFlight?.token == token else { return }
        inFlight = nil
    }
}
