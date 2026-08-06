import Foundation

// MARK: - What a sweep produces

/// One artifact, fully assessed: signature, notarization, and attributes.
///
/// The two halves travel together as **one value** rather than as two parallel
/// collections a surface has to join. The spec requires a quarantined artifact to
/// be presented alongside its signing verdict so the user can see why launch is
/// or is not blocked, and a value that carries both makes showing one without the
/// other impossible rather than merely discouraged.
public struct ArtifactIntegrityReport: Sendable, Hashable, Identifiable {
    public let signature: ArtifactSignatureAssessment
    /// `nil` when the attributes could not be read at all — deliberately **not**
    /// an empty `ArtifactQuarantine`, which would report a failed read as the
    /// positive fact "this artifact has no attributes".
    public let quarantine: ArtifactQuarantine?

    public init(signature: ArtifactSignatureAssessment, quarantine: ArtifactQuarantine?) {
        self.signature = signature
        self.quarantine = quarantine
    }

    public var location: ArtifactLocation { signature.location }
    public var id: URL { location.url }
    public var isQuarantined: Bool { quarantine?.isQuarantined ?? false }
}

public enum ArtifactIntegrityEvent: Sendable, Hashable {
    /// How many artifacts the run set out to assess.
    case started(count: Int)
    case assessed(ArtifactIntegrityReport)
    /// **Only ever emitted by a run that reached the end.** A cancelled run
    /// finishes its stream without this, so a consumer cannot mistake a partial
    /// sweep for a complete one.
    case finished
}

public typealias ArtifactIntegrityEventStream = AsyncThrowingStream<ArtifactIntegrityEvent, any Error>

// MARK: - The engine

/// Assesses artifacts one at a time, off the main actor, streaming as it goes.
///
/// `DiskUsageEngine.scan`'s shape verbatim, for the same reasons. A sweep is
/// hundreds of artifacts at tens of milliseconds each — the U3 probe measured 22
/// to 452 ms per bundle — so a terminal batch would be a multi-second freeze with
/// nothing on screen, and one broken artifact would take the whole run with it.
///
/// **Failure is per item.** A throwing inspector becomes a `.couldNotAssess`
/// report for *that* artifact and the run continues. The stream's `throws` is
/// reserved for cancellation, which is not a failure of any artifact.
public struct ArtifactIntegrityEngine: Sendable {
    private let signatures: any CodeSignatureInspecting
    private let quarantine: any QuarantineInspecting

    public init(
        signatures: any CodeSignatureInspecting = SecurityFrameworkSignatureInspector(),
        quarantine: any QuarantineInspecting = ExtendedAttributeQuarantineInspector()
    ) {
        self.signatures = signatures
        self.quarantine = quarantine
    }

    @concurrent
    public func inspect(_ locations: [ArtifactLocation]) async -> ArtifactIntegrityEventStream {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    try await produce(locations, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Terminating the stream cancels the producer. This is what makes
            // "stop consuming" a real cancellation rather than a leak, and it is
            // why a cancelled run never reaches `.finished`.
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }

    private func produce(
        _ locations: [ArtifactLocation],
        into continuation: ArtifactIntegrityEventStream.Continuation
    ) async throws {
        continuation.yield(.started(count: locations.count))

        for location in locations {
            // Per artifact, before any work for it. A cancelled sweep stops at the
            // next item rather than at the next hundred.
            try Task.checkCancellation()
            continuation.yield(.assessed(await report(for: location)))
        }

        continuation.yield(.finished)
    }

    /// One artifact's two questions, each answered independently.
    ///
    /// A signature that could not be read must not delete an attribute that was,
    /// and the reverse. They are two facts about one file, not one fact.
    private func report(for location: ArtifactLocation) async -> ArtifactIntegrityReport {
        let signature: ArtifactSignatureAssessment
        do {
            signature = try await signatures.assess(location)
        } catch let failure as ArtifactInspectionFailure {
            signature = Self.unassessed(location, reason: failure.reason)
        } catch is CancellationError {
            signature = Self.unassessed(location, reason: .cancelled)
        } catch {
            signature = Self.unassessed(location, reason: .inspectionFailed)
        }

        return ArtifactIntegrityReport(
            signature: signature,
            quarantine: try? await quarantine.inspect(location)
        )
    }

    /// Whatever went wrong, the artifact does not become signed or notarized.
    private static func unassessed(
        _ location: ArtifactLocation,
        reason: AssessmentUnavailableReason
    ) -> ArtifactSignatureAssessment {
        ArtifactSignatureAssessment(
            location: location,
            signing: .couldNotAssess(reason),
            notarization: .couldNotAssess(reason)
        )
    }
}
