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
    /// One click covering N operations (bulk-confirmation ruling 2026-09-01).
    /// Its own case per action rather than a reuse of `packageRemoval`: a
    /// disclosure claiming removal over an upgrade is the same class of wrong
    /// sentence D2 banned from the tap copy.
    case bulkAction(BulkSelection.Action, count: Int)
    /// The grouped bare `brew upgrade`, which names no package and moves every
    /// outdated one.
    case upgradeEverything

    public var warningText: String {
        switch self {
        case .packageRemoval:
            "This removes installed software."
        case .bulkAction(let action, let count):
            switch action {
            case .upgrade:
                """
                This starts \(count) upgrade \(count == 1 ? "operation" : "operations") \
                at once. Each runs separately and can be cancelled from Activity.
                """
            case .uninstall:
                // Unreachable through `submitBulk`, which routes uninstall
                // batches to `packageRemoval` — kept honest for totality.
                "This removes installed software."
            case .pin:
                """
                This pins \(count) \(count == 1 ? "formula" : "formulae") at \
                \(count == 1 ? "its" : "their") installed \
                \(count == 1 ? "version" : "versions") until you unpin \
                \(count == 1 ? "it" : "them").
                """
            case .unpin:
                """
                This unpins \(count) \(count == 1 ? "formula" : "formulae"), \
                so upgrades can move \(count == 1 ? "it" : "them") again.
                """
            }
        case .upgradeEverything:
            """
            This upgrades every outdated Homebrew formula and cask in one \
            operation, including any not shown by the current filters.
            """
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

    /// What this command declares **of its own** (design DD-3). `nil` for the
    /// two commands that have nothing to disclose — which is what lets a
    /// revocation lead a batch without downgrading the disclosure behind it.
    ///
    /// `disclosure` itself is no longer declared here at all: the protocol
    /// default derives it from this, so the two cannot disagree.
    public var declaredDisclosure: ConfirmationDisclosure? {
        switch self {
        case .addTap(let tap): .tapAdd(tap)
        case .trustTap(let tap): .tapTrustGrant(tap)
        case .removeTap, .untrustTap: nil
        case .forceRemoveTap(let evidence):
            .forceUntap(tap: evidence.tap, affected: evidence.affected)
        }
    }

    // MARK: - Actions, which are not commands

    /// What the **Untap** action means, whole: remove the tap, then revoke the
    /// grant it owned.
    ///
    /// **The order is load-bearing, and it runs this way round (maintainer
    /// decision D4, 2026-08-23).** `brew` refuses to untap a tap that still owns
    /// installed packages — `Refusing to untap acme/tools because it contains
    /// the following installed casks: …`, exit 1 on Homebrew 6.0.18. A
    /// revocation submitted *in front of* such a removal succeeds while the
    /// removal is refused, and the user is left holding the worst of both: the
    /// grant gone, the tap still installed, and Force Untap hidden because it is
    /// offered only for a tap whose packages Homebrew will still name (DD-14) —
    /// a loop whose only signposted exit was the Untap that had just failed.
    ///
    /// So the revocation is a **follower**, submitted only once the removal has
    /// settled as succeeded. A refused removal submits none of it: no phantom
    /// queue item for a command that never ran, and the failed removal carries
    /// brew's own reason. `OperationCenter.submitDependentSequence` is what
    /// enforces that; this factory only states the order.
    ///
    /// Behind a removal brew *accepted*, the revocation stays **unconditional**,
    /// because `brew untrust` on a never-trusted tap exits 0 (obs #7722) and
    /// because Cellar must not decide from a state it may be reading off a brew
    /// that reports none. Without it, untapping leaves a dormant, invisible
    /// grant in `trust.json` that a later re-tap — including one performed by a
    /// Brewfile import — silently re-arms with no new consent (tap-management
    /// TM7 :216-231, TM13.6). The grant therefore never outlives a successful
    /// removal; it merely outlives a refused one, which is the only state that
    /// still has a tap for it to belong to.
    public static func removal(of raw: String) -> [TapCommand]? {
        guard let tap = TapName(raw) else { return nil }
        return [.removeTap(tap), .untrustTap(tap)]
    }

    /// The same, with the force removal in place of the plain one (TM8 :281-283).
    ///
    /// With the removal leading, the sequence's `leadDisclosure` is the force
    /// untap's own `.forceUntap(tap:affected:)` directly rather than through the
    /// skip — the rule is unchanged, and it simply has nothing to skip here.
    public static func forcedRemoval(evidence: ForceUntapEvidence) -> [TapCommand]? {
        guard let forced = forceUntap(evidence: evidence) else { return nil }
        return [forced, .untrustTap(evidence.tap)]
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
