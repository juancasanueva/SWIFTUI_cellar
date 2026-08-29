import BrewProcess
import Catalog

// MARK: - Threat response: subprocess argument composition
//
// Every mutating `brew` invocation Cellar can produce is spelled in this file,
// as a typed case that lowers to an argv vector. Three properties hold by
// construction rather than by discipline (design D1, D2):
//
// 1. **argv, never a string.** `arguments` is handed to `BrewCommand.mutate` and
//    from there element-by-element to the process seam. Nothing joins, quotes,
//    interpolates or shells out, so a name containing a space, `;` or `$(…)`
//    stays one literal argument.
// 2. **The kind flag is always explicit.** Every command that names a package
//    passes `--formula` or `--cask`, so a token published in both namespaces —
//    `docker` is the live one — can never resolve to the wrong package. There is
//    no per-verb exception: `brew pin` and `brew unpin` both accept the flags
//    (live probe, brew 6.0.14).
// 3. **Names are refused at construction.** A name that is empty or begins with
//    `-` would be read by brew as an option wherever it sat in the vector, so
//    the failable factories reject it and no argv is ever built from it.
//
// `displayCommand` is **one-way**: it renders argv for a human to read or paste,
// and nothing in this module — or anywhere else — parses a command string back
// into arguments. That is what keeps the rendering incapable of changing what
// runs.

/// A package identity, proven safe to put in argv (design D9).
///
/// The four package-naming cases take this rather than a bare `PackageID`, so
/// an unvalidated command is **unrepresentable** rather than merely discouraged.
/// M2-2 made the same claim while two app-target call sites built cases straight
/// from a raw identity; fixing those two would have left the third one to come.
/// A guard the compiler enforces does not have a third one to come.
public struct PackageTarget: Sendable, Hashable {
    public let id: PackageID

    public var kind: PackageKind { id.kind }
    public var name: String { id.name }

    /// Fails when the name could be read by brew as an option rather than as a
    /// package, or when the identity belongs to another source. The single gate:
    /// `FormulaID` and `CaskID` are expressed over it, so `isSafe` has exactly
    /// one definition.
    ///
    /// The source guard is what keeps brew argv from ever naming an npm package.
    /// Refusing here makes the whole affordance unavailable — no bulk entry, no
    /// submitted upgrade, no command to cancel — rather than producing a
    /// well-formed `brew upgrade --formula typescript` for a package brew does
    /// not have (design D3).
    public init?(_ id: PackageID) {
        guard id.kind.source == .homebrew, MutationName.isSafe(id.name) else { return nil }
        self.id = id
    }

    public init?(kind: PackageKind, name: String) {
        self.init(PackageID(kind: kind, name: name))
    }
}

/// A formula, proven to be one.
///
/// The wrapper exists so "pin a cask" is unrepresentable rather than validated
/// at runtime — the same technique `CatalogFilterBar.KindSelection` uses for
/// "neither kind selected". It does no argv work: the kind flag comes from the
/// `PackageID` like every other command's.
public struct FormulaID: Sendable, Hashable {
    public let target: PackageTarget

    public var id: PackageID { target.id }
    public var name: String { id.name }

    /// Fails when `id` is a cask, or when its name could be read as an option.
    public init?(_ id: PackageID) {
        guard id.kind == .formula, let target = PackageTarget(id) else { return nil }
        self.target = target
    }

    public init?(name: String) {
        self.init(PackageID(kind: .formula, name: name))
    }
}

/// A cask, proven to be one.
///
/// `--zap` is cask-only in brew, so a formula literally cannot spell it.
public struct CaskID: Sendable, Hashable {
    public let target: PackageTarget

    public var id: PackageID { target.id }
    public var name: String { id.name }

    /// Fails when `id` is a formula, or when its name could be read as an option.
    public init?(_ id: PackageID) {
        guard id.kind == .cask, let target = PackageTarget(id) else { return nil }
        self.target = target
    }

    public init?(name: String) {
        self.init(PackageID(kind: .cask, name: name))
    }
}

/// The rule that decides whether a package name may reach argv.
///
/// **The premise this rule was written under no longer holds, and the rule is
/// unchanged anyway.** It used to argue that names come from brew's own
/// snapshot or from the catalog and never from free text, so this was a second
/// line of defence rather than the first. An imported Brewfile is a file the
/// user supplied, and it *is* a name source. That premise is restated here
/// deliberately rather than left stale where a future reader would trust it
/// (`package-mutation` PM9).
///
/// What did **not** change:
///
/// - No new construction path exists. A file-sourced name becomes a command
///   only by constructing the same `PackageTarget` / `FormulaID` / `CaskID` as
///   every other call site, and there is no convenience overload, no
///   "already validated" bypass, and no path carrying a raw file string into
///   argv.
/// - This gate is **not widened**. It still rejects exactly an empty name, a
///   name that begins with `-`, and a name containing whitespace. Widening it
///   to "alphanumeric only" would refuse names brew genuinely publishes
///   (`gcc@11`, `font-fira-code`, `python@3.12`), and `/` stays legal because a
///   real third-party dump is full of `user/repo/token` tokens.
/// - This gate is **not weakened** for a file-sourced name either. A name read
///   out of a Brewfile is subject to exactly these rules and, additionally, to
///   the parser's own literal grammar: `BrewfileParser.isRepresentableToken`
///   admits only the character set a Homebrew token is actually spelled with,
///   so a backtick, a `$(…)` or a `#{…}` interpolation becomes a **counted,
///   named refusal** at parse time and never reaches this function at all.
///
/// The defence in depth that matters most is still structural rather than
/// textual: `BrewCommand` is argv-only, so even a name that passed every rule
/// here would remain one literal argument and could never become a shell.
enum MutationName {
    static func isSafe(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-") else { return false }
        return !name.contains(where: \.isWhitespace)
    }
}

/// Every mutating `brew` command Cellar can issue.
///
/// There is no `upgradeSelected` case: a selection fans out into N ordinary
/// `.upgrade(id)` submissions at the call site, so each selected package gets
/// its own queue item, log, copy-command, cancel and terminal outcome, and a
/// mid-batch failure attributes to exactly one package (design D1, user ruling
/// 2026-08-02).
public enum MutationCommand: Sendable, Equatable {
    case install(PackageTarget)
    case uninstall(PackageTarget)
    case reinstall(PackageTarget)
    case upgrade(PackageTarget)
    /// `brew uninstall --cask --zap` — cask-only, and separately confirmed.
    case zap(CaskID)
    /// Plain `brew upgrade`: no name, no kind flag, brew's own defaults
    /// (product Q3).
    case upgradeAll
    /// Plain `brew update`: advances what the local brew *knows* — its cached
    /// API data and tap clones — and installs nothing. On the mutation spine
    /// rather than beside it because that knowledge is exactly what
    /// `brew info --installed` answers from, so a terminal must pay the same
    /// inventory re-snapshot every other case pays. The pinned
    /// `HOMEBREW_NO_AUTO_UPDATE=1` suppresses only the *implicit* update other
    /// verbs would run; it does not touch this explicit one.
    case update
    case pin(FormulaID)
    case unpin(FormulaID)

    // MARK: - Failable construction

    public static func install(formula name: String) -> MutationCommand? {
        FormulaID(name: name).map { .install($0.target) }
    }

    public static func install(cask name: String) -> MutationCommand? {
        CaskID(name: name).map { .install($0.target) }
    }

    public static func uninstall(formula name: String) -> MutationCommand? {
        FormulaID(name: name).map { .uninstall($0.target) }
    }

    public static func uninstall(cask name: String) -> MutationCommand? {
        CaskID(name: name).map { .uninstall($0.target) }
    }

    public static func reinstall(formula name: String) -> MutationCommand? {
        FormulaID(name: name).map { .reinstall($0.target) }
    }

    public static func upgrade(formula name: String) -> MutationCommand? {
        FormulaID(name: name).map { .upgrade($0.target) }
    }

    public static func upgrade(cask name: String) -> MutationCommand? {
        CaskID(name: name).map { .upgrade($0.target) }
    }

    public static func zap(cask name: String) -> MutationCommand? {
        CaskID(name: name).map { .zap($0) }
    }

    public static func pin(formula name: String) -> MutationCommand? {
        FormulaID(name: name).map { .pin($0) }
    }

    public static func unpin(formula name: String) -> MutationCommand? {
        FormulaID(name: name).map { .unpin($0) }
    }

    /// The safe way to build a command for a package identity the UI already
    /// holds, whichever verb it is.
    ///
    /// Returns `nil` when the identity could not survive argv composition, so a
    /// caller that cannot build one renders the affordance unavailable rather
    /// than failing at spawn time. Deliberately not named after any one verb:
    /// an overload called `upgrade(_:)` would collide with the case of the same
    /// name and silently recurse.
    public static func naming(
        _ id: PackageID,
        _ build: (PackageTarget) -> MutationCommand
    ) -> MutationCommand? {
        PackageTarget(id).map(build)
    }

    // MARK: - Projection

    /// The package this command acts on, when it acts on one.
    public var packageID: PackageID? {
        switch self {
        case .install(let target), .uninstall(let target), .reinstall(let target), .upgrade(let target):
            target.id
        case .zap(let cask):
            cask.id
        case .pin(let formula), .unpin(let formula):
            formula.id
        case .upgradeAll, .update:
            nil
        }
    }

    /// The verb this command is recorded and searched under.
    ///
    /// Deliberately **not** `arguments[0]`: `zap` and an ordinary uninstall both
    /// lower to `uninstall`, and a history row that called them the same thing
    /// would make the destructive one unfindable. `upgradeAll` names the grouped
    /// operation rather than the single package upgrade it shares a verb with
    /// (installation-history IH1, IH5).
    public var verb: String {
        switch self {
        case .install: Verb.install.rawValue
        case .uninstall: Verb.uninstall.rawValue
        case .reinstall: Verb.reinstall.rawValue
        case .upgrade: Verb.upgrade.rawValue
        case .zap: "zap"
        case .upgradeAll: "upgradeAll"
        case .update: Verb.update.rawValue
        case .pin: Verb.pin.rawValue
        case .unpin: Verb.unpin.rawValue
        }
    }

    /// The argv vector, excluding the `brew` executable itself.
    public var arguments: [String] {
        switch self {
        case .install(let target):
            [Verb.install.rawValue] + Self.vector(naming: target.id)
        case .uninstall(let target):
            [Verb.uninstall.rawValue] + Self.vector(naming: target.id)
        case .reinstall(let target):
            [Verb.reinstall.rawValue] + Self.vector(naming: target.id)
        case .upgrade(let target):
            [Verb.upgrade.rawValue] + Self.vector(naming: target.id)
        case .zap(let cask):
            [Verb.uninstall.rawValue, Flag.cask.rawValue, Flag.zap.rawValue, cask.name]
        case .upgradeAll:
            [Verb.upgrade.rawValue]
        case .update:
            [Verb.update.rawValue]
        case .pin(let formula):
            [Verb.pin.rawValue] + Self.vector(naming: formula.id)
        case .unpin(let formula):
            [Verb.unpin.rawValue] + Self.vector(naming: formula.id)
        }
    }

    /// The runnable form, always serialized as a mutation.
    public var brewCommand: BrewCommand {
        .mutate(arguments)
    }

    /// Whether this command destroys something and must be confirmed first.
    ///
    /// Exactly `uninstall` and `zap` (product Q2). `upgradeAll` is the only bulk
    /// command and is non-destructive, so no bulk destructive path exists.
    public var requiresConfirmation: Bool {
        switch self {
        case .uninstall, .zap: true
        case .install, .reinstall, .upgrade, .upgradeAll, .update, .pin, .unpin: false
        }
    }

    /// The command as a human reads it — and as they can paste it.
    ///
    /// Display only. Nothing parses this back into argv (see the file header),
    /// which is what makes the confirmation sheet and the copy-command
    /// affordance incapable of changing what runs.
    public var displayCommand: String {
        "brew " + arguments.joined(separator: " ")
    }

    // MARK: - Vector pieces

    /// Spelled as cases rather than literals so a typo is a compile error and
    /// the set of verbs Cellar can issue is enumerable by reading.
    private enum Verb: String {
        case install
        case uninstall
        case reinstall
        case upgrade
        case update
        case pin
        case unpin
    }

    private enum Flag: String {
        case formula = "--formula"
        case cask = "--cask"
        case zap = "--zap"
    }

    /// The kind flag and the name, in that order. The single place a package
    /// becomes two argv elements.
    private static func vector(naming id: PackageID) -> [String] {
        let flag: Flag = switch id.kind {
        case .formula: .formula
        case .cask: .cask
        // Unreachable by construction: every path here goes through a
        // `PackageTarget`, and its init refuses any identity whose source is not
        // Homebrew. Trapping rather than inventing a flag is the point — brew
        // has no argv that names an npm package, so there is no third answer
        // that would be correct, and a `default:` returning `[id.name]` would
        // quietly ship the wrong one (design D3).
        case .npm: preconditionFailure("brew argv cannot name an npm package")
        }
        return [flag.rawValue, id.name]
    }
}
