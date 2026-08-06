import Foundation
import Security

// MARK: - The seam

public protocol CodeSignatureInspecting: Sendable {
    func assess(_ location: ArtifactLocation) async throws -> ArtifactSignatureAssessment
}

// MARK: - The real one

/// Security.framework directly, and **no subprocess**.
///
/// `SecStaticCodeCreateWithPath` → `SecCodeCopySigningInformation` →
/// `SecStaticCodeCheckValidity`. There is no `codesign`, no `spctl`, no parsing
/// of anybody's textual output, and — per the U3 answer — **no
/// `SecAssessmentTicketLookup` call site**: the symbol is absent from the public
/// SDK, and reaching it through `dlsym` to work around that is not something this
/// app does.
///
/// Everything here is read-only. Nothing on disk is opened for writing, nothing
/// is relocated, and no authorization is ever requested — the U3 probe ran the
/// whole sequence at euid 501 with no prompt of any kind.
public struct SecurityFrameworkSignatureInspector: CodeSignatureInspecting {
    public init() {}

    public func assess(_ location: ArtifactLocation) async throws -> ArtifactSignatureAssessment {
        try Task.checkCancellation()

        var staticCode: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(location.url as CFURL, [], &staticCode)
        guard created == errSecSuccess, let code = staticCode else {
            let reason: AssessmentUnavailableReason = created == errSecCSBadObjectFormat
                ? .bundleFormatUnrecognized
                : .artifactUnreadable
            return ArtifactSignatureAssessment(
                location: location,
                signing: .couldNotAssess(reason),
                notarization: .couldNotAssess(reason)
            )
        }

        let signing = Self.signingState(of: code)
        try Task.checkCancellation()
        let stapled = Self.satisfies(code, requirement: Self.notarizedRequirement)

        return ArtifactSignatureAssessment(
            location: location,
            signing: signing,
            notarization: Self.notarization(signing: signing, stapledCheckPassed: stapled)
        )
    }

    // MARK: - The notarization rule

    /// What the stapled check plus the signing state honestly support.
    ///
    /// Internal-but-static and tested directly, because it is the whole of the U3
    /// amendment and it is not otherwise observable without a notarized artifact
    /// on hand.
    ///
    /// - A Developer ID signature whose stapled check **passes** is notarized.
    /// - A Developer ID signature whose stapled check **fails** is
    ///   `couldNotAssess`, never `notNotarized`: the ticket may simply not be
    ///   stapled, and the only API that could tell the difference is unavailable.
    /// - An **ad-hoc or unsigned** artifact is definitively not notarized —
    ///   notarization requires a Developer ID signature, so this asserts nothing
    ///   unproven.
    /// - An assessment that could not read the signature cannot answer this
    ///   question either, and does not pretend to.
    static func notarization(
        signing: ArtifactSigningState,
        stapledCheckPassed: Bool
    ) -> ArtifactNotarizationState {
        switch signing {
        case .signed:
            stapledCheckPassed ? .notarized : .couldNotAssess(.assessmentUnavailable)
        case .adHoc, .unsigned:
            .notNotarized
        case .invalid:
            .couldNotAssess(.assessmentUnavailable)
        case .couldNotAssess(let reason):
            .couldNotAssess(reason)
        }
    }

    // MARK: - Reading the signature

    private static func signingState(of code: SecStaticCode) -> ArtifactSigningState {
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation),
            &info
        )
        guard status == errSecSuccess, let dictionary = info as? [String: Any] else {
            return .couldNotAssess(status == errSecCSUnsigned ? .artifactUnreadable : .inspectionFailed)
        }
        guard let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String else {
            return .unsigned
        }

        if let invalidity = Self.invalidity(of: code) { return .invalid(invalidity) }

        // `kSecCodeSignatureAdhoc` is 0x2. Measured on every brew bottle during
        // the U3 probe: identifier `rg-<hash>`, no team, no authority chain.
        let flags = dictionary[kSecCodeInfoFlags as String] as? UInt32 ?? 0
        if flags & Self.adhocSignatureFlag != 0 {
            return .adHoc(identifier: identifier)
        }

        let authorities = (dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? [])
            .compactMap { SecCertificateCopySubjectSummary($0) as String? }
        return .signed(
            ArtifactSigningIdentity(
                identifier: identifier,
                teamIdentifier: dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
                authorities: authorities
            )
        )
    }

    /// Whether the signature itself fails to hold, and how.
    ///
    /// Checked against no requirement at all, so this asks only "does the
    /// signature match what is on disk and chain correctly" and not "is it
    /// anybody in particular".
    private static func invalidity(of code: SecStaticCode) -> SignatureInvalidity? {
        let status = SecStaticCodeCheckValidity(code, [], nil)
        switch status {
        case errSecSuccess, errSecCSUnsigned:
            return nil
        case errSecCSBadResource:
            return .brokenSeal
        case errSecCSSignatureFailed, errSecCSSignatureInvalid, errSecCSSignatureNotVerifiable:
            return .malformedSignature
        case errSecCertificateExpired:
            return .expiredCertificate
        case errSecCertificateRevoked:
            return .revokedCertificate
        default:
            return nil
        }
    }

    private static func satisfies(_ code: SecStaticCode, requirement text: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    /// The two requirements the design names.
    ///
    /// `notarized` is evaluated **locally**, against the stapled ticket and the
    /// code hashes: the U3 probe measured flat latency across five consecutive
    /// calls, scaling with bundle size rather than distance, and a definitive
    /// 20 ms failure for a non-notarized binary rather than a network timeout.
    /// `kSecCodeSignatureAdhoc`, which the Swift overlay does not export.
    ///
    /// Its value is fixed by the on-disk code-signing format rather than by a
    /// header, and the U3 probe read `flags: 2` from every brew bottle it
    /// inspected — so this constant is pinned to a measurement, not to a guess.
    static let adhocSignatureFlag: UInt32 = 0x2

    static let notarizedRequirement = "notarized"
    /// Signed by a certificate chaining to Apple's root — which every Developer
    /// ID artifact satisfies. Deliberately not `anchor apple`, which means
    /// *Apple's own system binary* and fails for every third-party app; both were
    /// measured during the probe because the two are one word apart.
    static let appleAnchorRequirement = "anchor apple generic"
}
