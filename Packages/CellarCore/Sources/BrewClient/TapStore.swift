import BrewProcess
import Foundation
import Observation

public enum TapLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case brewAbsent(InstalledAbsence)
    case failed(TapInventoryError)
}

@MainActor
@Observable
public final class TapStore {
    public private(set) var inventory: TapInventory = .empty
    public private(set) var state: TapLoadState = .idle

    public var absence: InstalledAbsence? {
        guard case .brewAbsent(let absence) = state else { return nil }
        return absence
    }

    @ObservationIgnored private let source: any TapPayloadSourcing

    private struct InFlightRefresh {
        let token: Int
        let request: URL
        let mark: Int
        let task: Task<Result<TapInventory, TapInventoryError>, Never>
    }

    @ObservationIgnored private var inFlight: InFlightRefresh?
    @ObservationIgnored private var nextToken = 0
    @ObservationIgnored private var installedSequence = 0
    @ObservationIgnored private var invalidationCount = 0

    public init(source: any TapPayloadSourcing = BrewTapPayloadSource()) {
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
        let outcome: Result<TapInventory, TapInventoryError>
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
            let acquisition = Task<Result<TapInventory, TapInventoryError>, Never> { [source, weak self] in
                defer { self?.vacate(token) }
                do {
                    let payload = try await source.payload(using: installation)
                    return .success(try await TapDecoder.decode(payload))
                } catch let error as TapInventoryError {
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

    private func adopt(_ outcome: Result<TapInventory, TapInventoryError>, token: Int) {
        guard token > installedSequence else { return }
        installedSequence = token
        switch outcome {
        case .success(let snapshot):
            inventory = snapshot
            state = .loaded
        case .failure(let error):
            state = .failed(error)
        }
    }

    private func clear(to absence: InstalledAbsence) {
        inFlight?.task.cancel()
        inFlight = nil
        nextToken += 1
        installedSequence = nextToken
        inventory = .empty
        state = .brewAbsent(absence)
    }

    private func vacate(_ token: Int) {
        guard inFlight?.token == token else { return }
        inFlight = nil
    }
}
