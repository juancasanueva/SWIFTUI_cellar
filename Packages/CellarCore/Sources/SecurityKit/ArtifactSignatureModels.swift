import Foundation

// MARK: - Values
//
// Split from `CodeSignatureInspecting.swift`, which crossed the 400-line rule
// once the real inspector landed. The split is along a real seam: everything
// here is a value with no dependency on Security.framework, so a reader deciding
// what a verdict *means* never has to read the code that produces it.

/// Who signed an artifact, as the platform reported it.
public struct ArtifactSigningIdentity: Sendable, Hashable, Codable {
    /// The code-signing identifier. Always present when there is a signature at
    /// all, including for an ad-hoc one.
    public let identifier: String
    /// The Developer ID team, when there is one. `nil` for ad-hoc signatures —
    /// an empty string here would read as "signed by nobody in particular"
    /// rather than "there is no team".
    public let teamIdentifier: String?
    /// The certificate chain, leaf first, exactly as the platform ordered it.
    public let authorities: [String]

    public init(identifier: String, teamIdentifier: String?, authorities: [String]) {
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.authorities = authorities
    }
}

/// Why an assessment reached no verdict.
///
/// Typed, exhaustive, and each with its own sentence. A shared "could not check"
/// would make five distinct situations indistinguishable in the panel, which is
/// the same as having one.
public enum AssessmentUnavailableReason: String, Sendable, Hashable, Codable, CaseIterable {
    /// The stapled check did not pass and the only API that could resolve the
    /// remaining question is not available.
    ///
    /// **This is the U3 answer.** `SecAssessmentTicketLookup` is present in the
    /// shipped `Security` binary and absent from the public macOS 26.5 SDK — no
    /// header, not in the module map — so a supported build cannot call it. A
    /// Developer ID artifact whose ticket is simply not stapled is therefore
    /// indistinguishable from one that was never notarized, and this app says so
    /// rather than picking one.
    case assessmentUnavailable
    /// The path could not be read at all.
    case artifactUnreadable
    /// The platform rejected the bundle's shape. Measured during the U3 probe on
    /// a real stale Caskroom directory: `-67028 bundle format unrecognized`.
    case bundleFormatUnrecognized
    /// The run was cancelled before this artifact was answered.
    case cancelled
    /// The platform returned an error this build has no more specific reading of.
    case inspectionFailed

    public var explanation: String {
        switch self {
        case .assessmentUnavailable:
            """
            No notarization ticket is stapled to this artifact, and this build cannot ask Apple \
            whether one exists. It may or may not be notarized.
            """
        case .artifactUnreadable:
            "The artifact could not be read from disk."
        case .bundleFormatUnrecognized:
            "macOS does not recognise this as a code bundle."
        case .cancelled:
            "The check was cancelled before this artifact was reached."
        case .inspectionFailed:
            "macOS reported an error this build cannot interpret further."
        }
    }
}

/// What is known about an artifact's signature.
///
/// Five cases, and `adHoc` is deliberately not folded into `unsigned`. The U3
/// probe measured that every brew formula binary is ad-hoc signed — that is the
/// *ordinary, correct* state of a bottle — and rendering the common case as a
/// failure would make the panel useless.
public enum ArtifactSigningState: Sendable, Hashable, Codable {
    case signed(ArtifactSigningIdentity)
    case adHoc(identifier: String)
    case unsigned
    case invalid(SignatureInvalidity)
    case couldNotAssess(AssessmentUnavailableReason)

    /// Whether an identified party signed this. **Only `signed` answers `true`**:
    /// an ad-hoc signature identifies nobody, and an inconclusive result
    /// identifies nothing at all.
    public var isSigned: Bool {
        if case .signed = self { return true }
        return false
    }

    public var identity: ArtifactSigningIdentity? {
        switch self {
        case .signed(let identity):
            identity
        case .adHoc(let identifier):
            ArtifactSigningIdentity(identifier: identifier, teamIdentifier: nil, authorities: [])
        case .unsigned, .invalid, .couldNotAssess:
            nil
        }
    }

    public var label: String {
        switch self {
        case .signed(let identity): "Signed by \(identity.teamIdentifier ?? identity.identifier)"
        case .adHoc: "Ad-hoc signed"
        case .unsigned: "Unsigned"
        case .invalid(let invalidity): invalidity.label
        case .couldNotAssess: "Could not assess"
        }
    }
}

/// Why a present signature does not hold.
public enum SignatureInvalidity: String, Sendable, Hashable, Codable, CaseIterable {
    /// The signature no longer matches the artifact's contents.
    case brokenSeal
    /// The signature itself could not be parsed.
    case malformedSignature
    case expiredCertificate
    case revokedCertificate
    /// A signature that does not chain to a trusted anchor.
    case untrustedAnchor

    public var label: String {
        switch self {
        case .brokenSeal: "Signature does not match contents"
        case .malformedSignature: "Malformed signature"
        case .expiredCertificate: "Signing certificate expired"
        case .revokedCertificate: "Signing certificate revoked"
        case .untrustedAnchor: "Signature does not chain to a trusted anchor"
        }
    }
}

/// What is known about an artifact's notarization.
public enum ArtifactNotarizationState: Sendable, Hashable, Codable {
    case notarized
    case notNotarized
    case couldNotAssess(AssessmentUnavailableReason)

    /// Both questions answer `false` for `couldNotAssess`, and that is the whole
    /// point: an inconclusive result must be counted as neither, and a caller
    /// asking either question gets an honest no.
    public var isNotarized: Bool {
        if case .notarized = self { return true }
        return false
    }

    public var isNotNotarized: Bool {
        if case .notNotarized = self { return true }
        return false
    }

    public var reason: AssessmentUnavailableReason? {
        guard case .couldNotAssess(let reason) = self else { return nil }
        return reason
    }

    public var label: String {
        switch self {
        case .notarized: "Notarized"
        case .notNotarized: "Not notarized"
        case .couldNotAssess: "Could not assess"
        }
    }
}

/// One artifact, assessed.
///
/// Not `Codable`, deliberately. Advisory outcomes are cached because re-fetching
/// them costs a network request; a signature assessment costs tens of
/// milliseconds of local work and re-reads the artifact as it is *now*. Caching
/// it would mean showing a verdict about bytes that may have changed since.
public struct ArtifactSignatureAssessment: Sendable, Hashable {
    public let location: ArtifactLocation
    public let signing: ArtifactSigningState
    public let notarization: ArtifactNotarizationState

    public init(
        location: ArtifactLocation,
        signing: ArtifactSigningState,
        notarization: ArtifactNotarizationState
    ) {
        self.location = location
        self.signing = signing
        self.notarization = notarization
    }
}

/// The three notarization counts, kept three.
///
/// Counting is where an inconclusive result usually becomes a verdict: a summary
/// reading "3 notarized, 2 not" over five artifacts, one of which could not be
/// assessed, has silently decided the fifth.
public struct NotarizationTotals: Sendable, Hashable {
    public let notarized: Int
    public let notNotarized: Int
    public let couldNotAssess: Int

    public init(of states: [ArtifactNotarizationState]) {
        var notarized = 0
        var notNotarized = 0
        var couldNotAssess = 0
        for state in states {
            switch state {
            case .notarized: notarized += 1
            case .notNotarized: notNotarized += 1
            case .couldNotAssess: couldNotAssess += 1
            }
        }
        self.notarized = notarized
        self.notNotarized = notNotarized
        self.couldNotAssess = couldNotAssess
    }

    public var total: Int { notarized + notNotarized + couldNotAssess }
}

/// A failure that prevented an artifact from being assessed at all.
public enum ArtifactInspectionFailure: Error, Sendable, Hashable {
    case artifactUnreadable
    case inspectionFailed

    public var reason: AssessmentUnavailableReason {
        switch self {
        case .artifactUnreadable: .artifactUnreadable
        case .inspectionFailed: .inspectionFailed
        }
    }
}
