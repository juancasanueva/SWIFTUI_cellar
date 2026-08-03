import BrewClient
import Foundation

extension HistoryRecord {
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
        return verb == MutationCommand.upgradeAll.verb ? .everyPackage : .noPackage
    }
}
