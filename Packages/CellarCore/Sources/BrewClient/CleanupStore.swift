import BrewProcess
import Foundation
import Observation
public enum CleanupPreviewState: Sendable, Equatable {
    case idle
    case loading(stale: CleanupPreviewResult?)
    case content(CleanupPreviewResult)
    case empty(CleanupPreviewResult)
    case partial(CleanupPreviewResult)
    case error(CleanupPreviewError, stale: CleanupPreviewResult?)
    case cancelled(stale: CleanupPreviewResult?)
    case stale(CleanupPreviewResult)
    public var result: CleanupPreviewResult? {
        switch self {
        case .content(let result), .empty(let result), .partial(let result), .stale(let result): result
        case .idle, .loading, .error, .cancelled: nil
        }
    }
    public var staleResult: CleanupPreviewResult? {
        switch self {
        case .loading(let stale), .error(_, let stale), .cancelled(let stale): stale
        case .stale(let result): result
        case .idle, .content, .empty, .partial: nil
        }
    }
    public var failure: CleanupPreviewError? {
        guard case .error(let error, _) = self else { return nil }
        return error
    }
}
@MainActor
@Observable
public final class CleanupStore {
    public private(set) var states: [CleanupScope: CleanupPreviewState] = [:]
    @ObservationIgnored private let source: any CleanupPreviewSourcing
    @ObservationIgnored private var tasks: [CleanupScope: Task<Void, Never>] = [:]
    @ObservationIgnored private var generations: [CleanupScope: UUID] = [:]
    @ObservationIgnored private var lastGood: [CleanupScope: CleanupPreviewResult] = [:]
    public init(source: any CleanupPreviewSourcing = CleanupPreviewSource()) { self.source = source }
    public func state(for scope: CleanupScope) -> CleanupPreviewState { states[scope] ?? .idle }
    @discardableResult
    public func startPreview(
        scope: CleanupScope,
        for detection: BrewDetectionState,
        diskUsage: CleanupDiskUsageContext? = nil
    ) -> UUID {
        tasks[scope]?.cancel()
        let generation = UUID()
        generations[scope] = generation
        states[scope] = .loading(stale: lastGood[scope])
        let request = CleanupPreviewRequest(scope: scope)
        tasks[scope] = Task { [weak self, source] in
            let outcome = await source.previewResult(
                request,
                for: detection,
                diskUsage: diskUsage
            )
            self?.adopt(outcome, scope: scope, generation: generation)
        }
        return generation
    }
    public func cancelPreview(for scope: CleanupScope) {
        tasks[scope]?.cancel(); tasks[scope] = nil
        generations[scope] = UUID()
        states[scope] = .cancelled(stale: lastGood[scope])
    }
    public func markStale(_ scope: CleanupScope) {
        tasks[scope]?.cancel(); tasks[scope] = nil
        generations[scope] = UUID()
        if let lastGood = lastGood[scope] { states[scope] = .stale(lastGood) }
    }
    /// Adopts queue-front authorization evidence without making it executable.
    /// A fresh preview is still required before a denied cleanup can be confirmed again.
    public func adopt(_ update: CleanupAuthorizationUpdate) {
        switch update {
        case .refreshed(let result):
            let scope = result.evidence.scope
            tasks[scope]?.cancel(); tasks[scope] = nil
            generations[scope] = UUID()
            lastGood[scope] = result
            states[scope] = .stale(result)
        case .stale(let reviewed, let error):
            let scope = reviewed.evidence.scope
            tasks[scope]?.cancel(); tasks[scope] = nil
            generations[scope] = UUID()
            lastGood[scope] = reviewed
            states[scope] = .error(error, stale: reviewed)
        }
    }
    private func adopt(
        _ outcome: Result<CleanupPreviewResult, CleanupPreviewError>,
        scope: CleanupScope,
        generation: UUID
    ) {
        guard generations[scope] == generation else { return }
        tasks[scope] = nil
        switch outcome {
        case .success(let result):
            lastGood[scope] = result
            if result.evidence.isPartial {
                states[scope] = .partial(result)
            } else if result.evidence.isEmpty {
                states[scope] = .empty(result)
            } else {
                states[scope] = .content(result)
            }
        case .failure(let error):
            if error.isCancellation {
                states[scope] = .cancelled(stale: lastGood[scope])
            } else {
                states[scope] = .error(error, stale: lastGood[scope])
            }
        }
    }
}
