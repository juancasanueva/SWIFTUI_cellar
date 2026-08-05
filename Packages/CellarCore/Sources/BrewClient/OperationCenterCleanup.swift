import BrewProcess
import Catalog
import DiskUsage
import Foundation

/// User-visible effects carried as typed facts rather than inferred from prose.
public struct CleanupEffect: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let removesCleanupCandidates = Self(rawValue: 1 << 0)
    public static let removesCachedDownloadsRegardlessOfAge = Self(rawValue: 1 << 1)
    public static let removesUnusedFormulae = Self(rawValue: 1 << 2)
}

/// The exact preview facts a user reviews before cleanup can join the FIFO.
public struct CleanupConfirmationDisclosure: Sendable, Equatable {
    public static let fullCleanupWarning =
        "Full cleanup uses --prune=all: it removes cached downloads regardless of age, "
        + "may remove downloads for installed packages, and is not cache-only."

    public let reviewedResult: CleanupPreviewResult
    public let effects: CleanupEffect
    public let orphanNames: [String]
    public let orphanCount: Int?

    public var previewRequest: CleanupPreviewRequest {
        CleanupPreviewRequest(id: reviewedResult.requestID, scope: reviewedResult.evidence.scope)
    }
    public var evidence: CleanupEvidence { reviewedResult.evidence }
    public var provenance: CleanupParserProvenance { reviewedResult.provenance }
    public var scope: CleanupScope { reviewedResult.evidence.scope }
    public var total: CleanupReportedTotal { evidence.total }
    public var fullWarning: String? { scope == .full ? Self.fullCleanupWarning : nil }
    public var warningText: String {
        switch scope {
        case .full: Self.fullCleanupWarning
        case .autoremove: "This removes formulae that are no longer required dependencies."
        case .global, .package: "This removes the cleanup candidates listed in the preview."
        }
    }

    init(result: CleanupPreviewResult) {
        reviewedResult = result
        effects = switch result.evidence.scope {
        case .global, .package: [.removesCleanupCandidates]
        case .full: [.removesCleanupCandidates, .removesCachedDownloadsRegardlessOfAge]
        case .autoremove: [.removesUnusedFormulae]
        }
        switch result.evidence.orphans {
        case .known(let names, let count, _):
            orphanNames = names
            orphanCount = count
        case .notApplicable, .unknown:
            orphanNames = []
            orphanCount = nil
        }
    }
}

/// Fresh evidence for adoption, or the reviewed evidence marked stale with its reason.
public enum CleanupAuthorizationUpdate: Sendable, Equatable {
    case refreshed(CleanupPreviewResult)
    case stale(reviewed: CleanupPreviewResult, error: CleanupPreviewError)
}

/// Revalidates the exact typed preview at the FIFO front before one possible spawn.
public struct CleanupLaunchAuthorizer: MutationLaunchAuthorizing {
    private let disclosure: CleanupConfirmationDisclosure
    private let source: any CleanupPreviewSourcing
    private let detection: BrewDetectionState
    private let diskUsage: CleanupDiskUsageContext?
    private let publish: @MainActor @Sendable (CleanupAuthorizationUpdate) -> Void

    public init(
        disclosure: CleanupConfirmationDisclosure,
        source: any CleanupPreviewSourcing,
        detection: BrewDetectionState,
        diskUsage: CleanupDiskUsageContext? = nil,
        publish: @escaping @MainActor @Sendable (CleanupAuthorizationUpdate) -> Void = { _ in }
    ) {
        self.disclosure = disclosure
        self.source = source
        self.detection = detection
        self.diskUsage = diskUsage
        self.publish = publish
    }

    public func authorizeLaunch() async -> MutationLaunchDecision {
        let outcome = await source.previewResult(
            disclosure.previewRequest,
            for: detection,
            diskUsage: diskUsage
        )
        switch outcome {
        case .success(let refreshed):
            await publish(.refreshed(refreshed))
            guard !refreshed.evidence.isEmpty,
                  !refreshed.evidence.isPartial,
                  disclosure.evidence.isEqualForAuthorization(to: refreshed.evidence)
            else {
                return .deny(.init(code: .evidenceChanged))
            }
            return .allow
        case .failure(let error):
            await publish(.stale(reviewed: disclosure.reviewedResult, error: error))
            return .deny(.init(code: .evidenceUnavailable))
        }
    }
}

extension OperationCenter {
    /// Presents cleanup confirmation only for current, complete, nonempty evidence.
    @discardableResult
    public func requestCleanup(preview state: CleanupPreviewState) -> ConfirmationRequest? {
        guard case .content(let result) = state,
              !result.evidence.isEmpty,
              !result.evidence.isPartial
        else { return nil }
        let command = CleanupCommand(scope: result.evidence.scope)
        let request = ConfirmationRequest(
            id: UUID(),
            command: AnyBrewMutation(command),
            additional: [],
            cleanupDisclosure: CleanupConfirmationDisclosure(result: result)
        )
        setPendingConfirmation(request)
        return request
    }

    /// Consumes one reviewed cleanup request and submits it with queue-front revalidation.
    @discardableResult
    public func confirmCleanup(
        _ request: ConfirmationRequest,
        source: any CleanupPreviewSourcing,
        detection: BrewDetectionState,
        diskUsage: CleanupDiskUsageContext? = nil,
        publish: @escaping @MainActor @Sendable (CleanupAuthorizationUpdate) -> Void = { _ in }
    ) -> ActivityItem? {
        guard pendingConfirmation == request,
              request.additional.isEmpty,
              let disclosure = request.cleanupDisclosure
        else { return nil }
        let command = CleanupCommand(scope: disclosure.scope)
        guard request.command == AnyBrewMutation(command) else { return nil }

        confirmations.consume(request)
        return submit(
            command,
            authorizer: CleanupLaunchAuthorizer(
                disclosure: disclosure,
                source: source,
                detection: detection,
                diskUsage: diskUsage,
                publish: publish
            ),
            refreshToken: MutationOperationToken()
        )
    }
}
