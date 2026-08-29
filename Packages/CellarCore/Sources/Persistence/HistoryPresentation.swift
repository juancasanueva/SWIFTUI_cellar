import BrewClient
import Catalog
import Foundation

extension HistoryRecord {
    /// Which package manager ran this operation, derived from the identity the
    /// row already stores.
    ///
    /// Derived rather than stored: `kindRaw` is the durable fact, and a second
    /// column recording the source could disagree with it after a migration.
    /// A row with no identity — a grouped upgrade, a service toggle, a cleanup —
    /// has no source to claim, so it falls back to Homebrew, which is the only
    /// manager any of those verbs has ever belonged to (design D12).
    public var source: PackageSource { packageID?.kind.source ?? .homebrew }

    /// The badge a row carries, naming the manager that ran it.
    public var sourceLabel: String { source.displayName }

    /// The command as a person reads it, and as the copy affordance produces it.
    ///
    /// **One-way**, exactly like `BrewMutating.displayCommand`: the prefix comes
    /// from the derived source and the rest is the stored argv joined. Nothing
    /// anywhere parses this back into a command, which is what keeps a history
    /// row incapable of running anything.
    public var displayCommand: String { source.commandName + " " + commandText }

    enum CleanupAction: String {
        case global = "cleanupGlobal"
        case package = "cleanupPackage"
        case full = "cleanupFull"
        case autoremove = "cleanupAutoremove"

        var label: String {
            switch self {
            case .global: "Cleanup"
            case .package: "Package cleanup"
            case .full: "Full cleanup"
            case .autoremove: "Autoremove"
            }
        }
    }

    /// Human-readable action vocabulary shared by every history surface.
    public var actionLabel: String {
        CleanupAction(rawValue: verb)?.label ?? verb
    }

    /// Human-readable terminal vocabulary shared by every history surface.
    ///
    /// Source-aware in exactly the two places the source changes what happened:
    /// an exit status belongs to the program that produced it, and a permissions
    /// refusal names the command a person would have to re-run in Terminal.
    /// Every other label is source-neutral already, and Homebrew's wording is
    /// unchanged character for character (`installation-history`).
    public var outcomeLabel: String {
        switch outcomeRaw {
        case "succeeded": "Done"
        case "noChange": "No change"
        case "failed":
            switch source {
            case .homebrew: exitStatus.map { "Failed (\($0))" } ?? "Failed"
            case .npm: exitStatus.map { "npm failed (\($0))" } ?? "npm failed"
            }
        case "busy": "Homebrew busy"
        case "needsPrivileges":
            switch source {
            case .homebrew: "Needs Terminal"
            case .npm: "Needs npm in Terminal"
            }
        case "networkUnavailable": "No network"
        case "cancelled": "Cancelled"
        case "abandoned": "Cancelled, still running"
        case "launchFailed": "Could not start"
        case "authorizationDeniedEvidenceChanged": "Needs fresh confirmation"
        case "authorizationDeniedEvidenceUnavailable": "Could not verify current packages"
        default: outcomeRaw
        }
    }

    /// What one durable entry acted on, as **three** distinct facts.
    ///
    /// V1 storage spells absence as the empty string, and two entirely different
    /// operations arrive at it: a grouped `upgradeAll`, which names no package
    /// because it targets *every* package, and a non-package family — the
    /// service verbs — which names no package because it has **no package
    /// identity at all** (installation-history IH1, service-management SM12).
    ///
    /// `name == ""` cannot tell those apart, so a projection that reads only the
    /// name renders `brew services stop atuin` as "All packages": a false claim
    /// about what happened, and precisely the borrowed identity IH1 forbids
    /// storage from synthesizing. The **verb** can tell them apart, so the verb
    /// is what decides.
    public enum Subject: Sendable, Equatable, Hashable {
        /// The entry names this package.
        case package(String)
        /// A grouped operation over every installed package.
        case everyPackage
        /// The operation has no package identity. Nothing is inferred for it.
        case noPackage
        /// A non-package operation whose stored verb defines its scope.
        case operationScope(String)

        /// The row's headline.
        ///
        /// "No package" and "All packages" are deliberately a matched pair in
        /// one slot: they are opposite answers to the same question, and a
        /// reader who sees one has already learned how to read the other.
        public var label: String {
            switch self {
            case .package(let name): name
            case .everyPackage: "All packages"
            case .noPackage: "No package"
            case .operationScope(let label): label
            }
        }
    }

    /// The entry's subject, decided by identity first and verb second.
    ///
    /// The grouped label is **opt-in by verb**, never a default: an entry whose
    /// verb this build does not recognise degrades to `.noPackage`, because
    /// under-claiming is cheap and telling a user that one service toggle
    /// touched every package on the machine is not.
    public var subject: Subject {
        guard name.isEmpty else { return .package(name) }
        return switch verb {
        case MutationCommand.upgradeAll.verb: .everyPackage
        // Homebrew itself is the subject: not one package and — unlike the
        // grouped upgrade — not every package either.
        case MutationCommand.update.verb: .operationScope("Homebrew")
        default:
            CleanupAction(rawValue: verb).map { .operationScope($0.label) } ?? .noPackage
        }
    }

    struct CleanupLabelMatches {
        let global: Bool
        let package: Bool
        let full: Bool
        let autoremove: Bool
    }

    static func cleanupLabelMatches(_ term: String) -> CleanupLabelMatches {
        CleanupLabelMatches(
            global: CleanupAction.global.label.localizedStandardContains(term),
            package: CleanupAction.package.label.localizedStandardContains(term),
            full: CleanupAction.full.label.localizedStandardContains(term),
            autoremove: CleanupAction.autoremove.label.localizedStandardContains(term)
        )
    }
}
