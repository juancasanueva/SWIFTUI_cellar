import Foundation

@testable import SecurityKit

/// A quarantine reader that answers from an arranged raw value, or refuses.
///
/// Kept apart from `FakeSignatureInspector` so a test can fail one half and leave
/// the other standing — which is exactly the isolation the engine has to provide.
actor FakeQuarantineInspector: QuarantineInspecting {
    private let rawValue: String?
    private let attributeNames: [String]
    private let failure: ArtifactInspectionFailure?
    private(set) var inspectedURLs: [URL] = []

    init(
        rawValue: String? = nil,
        attributeNames: [String]? = nil,
        failure: ArtifactInspectionFailure? = nil
    ) {
        self.rawValue = rawValue
        self.attributeNames = attributeNames
            ?? (rawValue == nil ? [] : [QuarantineAttribute.attributeName])
        self.failure = failure
    }

    func inspect(_ location: ArtifactLocation) async throws -> ArtifactQuarantine {
        inspectedURLs.append(location.url)
        try Task.checkCancellation()
        if let failure { throw failure }
        return ArtifactQuarantine(
            location: location,
            attributeNames: attributeNames,
            quarantine: rawValue.map { QuarantineAttribute(rawValue: $0) }
        )
    }
}
