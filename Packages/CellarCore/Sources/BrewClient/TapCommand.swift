import BrewProcess
import Catalog
import DiskUsage
import Foundation

public struct TapName: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String
    public var description: String { rawValue }

    public init?(_ rawValue: String) {
        guard MutationName.isSafe(rawValue) else { return nil }
        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              components.allSatisfy(Self.isCanonicalComponent)
        else { return nil }
        self.rawValue = rawValue
    }

    private static func isCanonicalComponent(_ component: Substring) -> Bool {
        guard let first = component.first,
              first.isASCII,
              first.isLetter || first.isNumber
        else { return false }
        return component.allSatisfy { character in
            character.isASCII
                && (character.isLetter || character.isNumber || "._-".contains(character))
        }
    }
}

public struct ForceUntapEvidence: Sendable, Equatable {
    public let tap: TapName
    public let affected: Set<PackageID>
    public let isComplete: Bool

    public init(tap: TapName, affected: Set<PackageID>, isComplete: Bool) {
        self.tap = tap
        self.affected = affected
        self.isComplete = isComplete
    }
}

/// `Hashable` rather than merely `Equatable` because `AnyBrewMutation` now
/// stores one, and that erased value is `Hashable` — carried in sets and used as
/// a dictionary key by the spine's callers. Both payloads were already hashable
/// (`TapName`, `Set<PackageID>`), so the conformance is synthesised and no
/// equality semantics change.
public enum ConfirmationDisclosure: Sendable, Hashable {
    case packageRemoval
    /// What `brew tap` does, and — the part the shipped copy got wrong — what
    /// it does **not** do (**D2**).
    case tapAdd(TapName)
    /// What `brew trust` does. A separate case because it is a separate answer
    /// to a separate question, and a user must be able to tell which one they
    /// gave (tap-management TM13).
    case tapTrustGrant(TapName)
    case forceUntap(tap: TapName, affected: Set<PackageID>)

    public var warningText: String {
        switch self {
        case .packageRemoval:
            "This removes installed software."
        case .tapAdd(let tap):
            """
            Adding \(tap.rawValue) clones a third-party repository. Homebrew \
            will not load its formulae or casks until you trust it, and Cellar \
            does not trust it for you.
            """
        case .tapTrustGrant(let tap):
            """
            Trusting \(tap.rawValue) lets Homebrew load and run its formulae \
            and casks. That is third-party code running as you, with your \
            permissions.
            """
        case .forceUntap(let tap, let affected):
            "Force-removing \(tap.rawValue) affects \(affected.count) installed packages."
        }
    }
}

public enum TapCommand: Sendable, Equatable, BrewMutating {
    case addTap(TapName)
    /// `brew trust` — the grant, and the only command in this capability that
    /// *increases* what Homebrew is willing to run.
    case trustTap(TapName)
    /// `brew untrust` — the revocation.
    case untrustTap(TapName)
    case removeTap(TapName)
    case forceRemoveTap(ForceUntapEvidence)

    public static func add(_ raw: String) -> TapCommand? {
        TapName(raw).map(TapCommand.addTap)
    }

    public static func trust(_ raw: String) -> TapCommand? {
        TapName(raw).map(TapCommand.trustTap)
    }

    public static func untrust(_ raw: String) -> TapCommand? {
        TapName(raw).map(TapCommand.untrustTap)
    }

    public static func untap(_ raw: String) -> TapCommand? {
        TapName(raw).map(TapCommand.removeTap)
    }

    public static func forceUntap(evidence: ForceUntapEvidence) -> TapCommand? {
        guard evidence.isComplete, !evidence.affected.isEmpty else { return nil }
        return .forceRemoveTap(evidence)
    }

    public var arguments: [String] {
        switch self {
        case .addTap(let tap): ["tap", tap.rawValue]
        case .trustTap(let tap): ["trust", tap.rawValue]
        case .untrustTap(let tap): ["untrust", tap.rawValue]
        case .removeTap(let tap): ["untap", tap.rawValue]
        case .forceRemoveTap(let evidence): ["untap", "--force", evidence.tap.rawValue]
        }
    }

    public var verb: String {
        switch self {
        case .addTap: "tapAdd"
        case .trustTap: "tapTrust"
        case .untrustTap: "tapUntrust"
        case .removeTap: "tapUntap"
        case .forceRemoveTap: "tapForceUntap"
        }
    }

    /// Always `nil`: trust is a property of a **tap**, never of a package
    /// (tap-management TM13 :479-480). This is also what keeps a `/`-qualified
    /// package token out of every tap argv by construction.
    public var packageID: PackageID? { nil }

    public var requiresConfirmation: Bool {
        switch self {
        case .addTap, .trustTap, .forceRemoveTap: true
        // A revocation only *reduces* authority, so asking for it would teach
        // the user to dismiss the sheet that matters (TM13 :487-488).
        case .removeTap, .untrustTap: false
        }
    }

    /// A grant and a revocation both change what `brew info --installed`
    /// reports as a package's `tap` — Homebrew withholds it while the tap is
    /// untrusted (obs #7724) — so both invalidate installed inventory as well as
    /// taps (TM9 :344-352). No tap command ever invalidates the catalog.
    public var invalidates: InvalidationScope {
        switch self {
        case .addTap, .removeTap: .taps
        case .trustTap, .untrustTap: [.taps, .installedInventory]
        case .forceRemoveTap: [.taps, .installedInventory, .diskUsage]
        }
    }

    public var diskAreas: Set<DiskArea> {
        guard case .forceRemoveTap(let evidence) = self else { return [] }
        return Set(evidence.affected.map { $0.kind == .formula ? .cellar : .caskroom })
    }

    public var disclosure: ConfirmationDisclosure {
        switch self {
        case .addTap(let tap): .tapAdd(tap)
        case .trustTap(let tap): .tapTrustGrant(tap)
        case .removeTap, .untrustTap: .packageRemoval
        case .forceRemoveTap(let evidence):
            .forceUntap(tap: evidence.tap, affected: evidence.affected)
        }
    }
}

public struct ForceUntapLaunchAuthorizer: MutationLaunchAuthorizing {
    private let tap: TapName
    private let expected: Set<PackageID>
    private let currentEvidence: @Sendable () async -> ForceUntapEvidence?

    public init(
        tap: TapName,
        expected: Set<PackageID>,
        currentEvidence: @escaping @Sendable () async -> ForceUntapEvidence?
    ) {
        self.tap = tap
        self.expected = expected
        self.currentEvidence = currentEvidence
    }

    public func authorizeLaunch() async -> MutationLaunchDecision {
        guard let evidence = await currentEvidence(),
              evidence.isComplete,
              evidence.tap == tap
        else {
            return .deny(MutationLaunchDenial(code: .evidenceUnavailable))
        }
        guard evidence.affected == expected else {
            return .deny(MutationLaunchDenial(code: .evidenceChanged))
        }
        return .allow
    }
}
