import Foundation

@testable import SecurityKit

/// A signature inspector that answers whatever it was told to.
///
/// Every path the matrix needs — including the ones a real machine will not
/// produce on demand, such as a revoked certificate — is reachable through this
/// fake. It counts its calls, so "one assessment per artifact" is a countable
/// fact rather than an assumption.
actor FakeSignatureInspector: CodeSignatureInspecting {
    private let result: ArtifactSignatureAssessmentBody?
    private let failure: ArtifactInspectionFailure?
    /// When non-empty, only these URLs fail. That is what makes per-artifact
    /// isolation testable: one broken item among several healthy ones.
    private let failingURLs: Set<URL>
    /// After this many assessments, block until cancelled.
    ///
    /// Deterministic cancellation without a sleep race: the run is *guaranteed*
    /// to be mid-flight when `cancel()` arrives, rather than probably mid-flight
    /// because the fake happened to be slower than the test's timer.
    private let blockAfter: Int?
    private(set) var assessedURLs: [URL] = []

    init(
        result: ArtifactSignatureAssessmentBody? = nil,
        failure: ArtifactInspectionFailure? = nil,
        failingURLs: Set<URL> = [],
        blockAfter: Int? = nil
    ) {
        self.result = result
        self.failure = failure
        self.failingURLs = failingURLs
        self.blockAfter = blockAfter
    }

    var assessmentCount: Int { assessedURLs.count }

    func assess(_ location: ArtifactLocation) async throws -> ArtifactSignatureAssessment {
        assessedURLs.append(location.url)
        if let blockAfter, assessedURLs.count > blockAfter {
            // Interrupted the instant the run is cancelled, and never otherwise.
            try await Task.sleep(for: .seconds(600))
        }
        try Task.checkCancellation()
        if let failure, failingURLs.isEmpty || failingURLs.contains(location.url) {
            throw failure
        }
        let body = result ?? ArtifactSignatureAssessmentBody(
            signing: .unsigned,
            notarization: .notNotarized
        )
        return ArtifactSignatureAssessment(
            location: location,
            signing: body.signing,
            notarization: body.notarization
        )
    }
}

/// The signing/notarization pair on its own, so a fake can be arranged without
/// naming a location it does not care about.
struct ArtifactSignatureAssessmentBody: Sendable {
    let signing: ArtifactSigningState
    let notarization: ArtifactNotarizationState
}
