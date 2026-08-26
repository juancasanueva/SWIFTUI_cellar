import BrewProcess
import Catalog

// MARK: - Threat response: subprocess argument composition, second family
//
// Every mutating `brew services` invocation Cellar can produce is spelled in
// this file, as a typed case that lowers to an argv vector. The three properties
// `MutationCommand.swift` establishes hold here identically, and one more holds
// that packages do not need:
//
// 1. **argv, never a string.** `arguments` is a vector of literal tokens plus
//    one validated name. Nothing joins, quotes, interpolates or shells out.
// 2. **Names are refused at construction.** `ServiceTarget` is expressed over
//    the same `MutationName.isSafe` gate `PackageTarget` is, so `isSafe` still
//    has exactly one definition in the module.
// 3. **`displayCommand` is one-way**, inherited from `BrewMutating`.
// 4. **`--all` is unrepresentable.** No case omits a target, so no value of this
//    type acts on more than one service. That is the structural answer to the
//    `upgradeAll` trap: one invocation per service, in selection order, each
//    with its own queue item, log, cancel and terminal outcome (M2 fan-out
//    ruling, package-mutation PM2 sc2).

/// A service name, proven safe to put in argv.
///
/// The services detail probe is the **only parameterised read argv** in the
/// codebase, so the guarantee `PackageTarget` gives the mutating commands has
/// to hold there too — and it holds the same way, through the one
/// `MutationName.isSafe` gate. An unvalidated services read or write is
/// unrepresentable rather than merely discouraged.
///
/// A service is its own entity: this is deliberately **not** a `PackageID`, and
/// nothing derives one from the other (service-management SM12).
///
/// It lives beside the commands rather than beside the read sources because
/// this is the file whose whole subject is "what may reach argv" — and because
/// the structural scan that enforces that rule reads `*Command.swift`.
public struct ServiceTarget: Sendable, Hashable {
    public let name: String

    /// Fails when the name could be read by brew as an option rather than as a
    /// service — which includes a name equal to `--all`.
    public init?(name: String) {
        guard MutationName.isSafe(name) else { return nil }
        self.name = name
    }

    /// Lifts a decoded record into a target, when its name survives the gate.
    public init?(_ record: ServiceRecord) {
        self.init(name: record.name)
    }
}

/// Every mutating `brew services` command Cellar can issue.
///
/// Exactly four, and the product names exactly four (PRD §3.3). `brew services
/// kill` and `brew services stop --keep` are deliberately **out**: both mean
/// "stop but stay registered", which has no PRD surface, and a third and fourth
/// stop-ish verb whose difference is registration is not something this surface
/// should ask a user to reason about.
///
/// `start` registers the service to launch at login; `run` does not. That is a
/// difference to the user's login items, so it is two separately labelled,
/// separately invoked actions rather than one verb with a flag (SM5).
public enum ServiceCommand: Sendable, Equatable, BrewMutating {
    /// `brew services start` — runs it now **and** registers it at login.
    case start(ServiceTarget)
    /// `brew services run` — runs it now and registers nothing.
    case run(ServiceTarget)
    case stop(ServiceTarget)
    case restart(ServiceTarget)

    // MARK: - Failable construction

    public static func start(service name: String) -> ServiceCommand? {
        ServiceTarget(name: name).map(Self.start)
    }

    public static func run(service name: String) -> ServiceCommand? {
        ServiceTarget(name: name).map(Self.run)
    }

    public static func stop(service name: String) -> ServiceCommand? {
        ServiceTarget(name: name).map(Self.stop)
    }

    public static func restart(service name: String) -> ServiceCommand? {
        ServiceTarget(name: name).map(Self.restart)
    }

    /// All four verbs for one service, in the order the row offers them.
    ///
    /// Spelled once, here, so a test asserting "exactly four" and a view drawing
    /// four controls are reading the same list rather than two lists that agree
    /// today.
    public static func allVerbs(for target: ServiceTarget) -> [ServiceCommand] {
        [.start(target), .run(target), .stop(target), .restart(target)]
    }

    // MARK: - Projection

    /// The service this command acts on. Every case has one — which is what
    /// makes `--all` unrepresentable.
    public var target: ServiceTarget {
        switch self {
        case .start(let target), .run(let target), .stop(let target), .restart(let target):
            target
        }
    }

    /// A service is never a package, so this is always `nil` (ruling #7180 a,
    /// SM12). The history entry it produces carries a **null** package identity
    /// rather than the service's name in a package's place.
    public var packageID: PackageID? { nil }

    /// The verb this command is recorded and searched under.
    ///
    /// Namespaced on the `upgradeAll` precedent, so a history search cannot
    /// confuse a service verb with a package one and so a future package verb
    /// called `start` could not collide with this (installation-history IH1,
    /// IH5).
    public var verb: String {
        switch self {
        case .start: "serviceStart"
        case .run: "serviceRun"
        case .stop: "serviceStop"
        case .restart: "serviceRestart"
        }
    }

    /// The argv vector, excluding the `brew` executable itself.
    ///
    /// Three elements, always: the literal subcommand, a literal verb token, and
    /// the validated name as its own final element.
    public var arguments: [String] {
        [Subcommand.services.rawValue, token.rawValue, target.name]
    }

    /// **False for all four, recorded rather than silent.** None of them
    /// destroys anything, each is reversible in one click, and start-versus-run
    /// is already an explicit user choice rather than a side effect. The
    /// confirmation gate stays restricted to uninstall and zap
    /// (package-mutation PM3, unchanged).
    public var requiresConfirmation: Bool { false }

    /// Starting or stopping a service changes nothing in the installed set, so
    /// the inventory probe could not observe a difference (design D2, SM8).
    public var invalidates: InvalidationScope { .services }

    // MARK: - Classification (design D4 — SM6, SM7)

    /// Reads this family's own markers on exit 0, then falls through to the
    /// shared default.
    ///
    /// **Why an override rather than a change to the default.** `brew services`
    /// exits **0** both for a state change and for a no-op — live probe, brew
    /// 6.0.14, gate U8 — so the exit code alone cannot classify a service verb.
    /// The shipped default returns `.succeeded` for exit 0 *before* reading a
    /// byte of prose, which is exactly right for `install` and exactly wrong
    /// here.
    ///
    /// **Why the scan widens to stdout, and why that is contained.** The shipped
    /// rule is stderr-only precisely so a package's build script cannot change
    /// what the user is told, and `already started, use` arrives on **stdout**.
    /// `brew services` runs no third-party build script: its stdout is brew's
    /// own prose plus launchctl's. The widening is confined to this override, so
    /// it cannot reach `install`/`upgrade` — a claim made falsifiable by
    /// `packageClassificationIsByteIdentical` and
    /// `aPayloadContainingAServiceMarkerCannotReclassifyAnInstall`.
    ///
    /// Nothing is extracted from the payload: the markers are membership tests,
    /// and the sentence the user sees is built from this typed command.
    public func classify(
        exit: BrewExit,
        fault: BrewProcessError?,
        log: [LogLine]
    ) -> MutationOutcome {
        // Only on a clean exit, and only after the structural facts. A fault, a
        // cancellation or a non-zero status is decided by the default, so a
        // marker can never rescue a failure or mask a cancel.
        guard fault == nil, exit.isSuccess, Marker.isNoChange(in: log) else {
            return MutationOutcome.classify(exit: exit, fault: fault, log: log)
        }
        return .noChange
    }

    /// The phrases brew emits when it did nothing, and the only bytes of the
    /// payload this family looks at.
    ///
    /// Matched with `contains` on an **interior invariant** — never anchored,
    /// never whole-sentence — because brew interpolates the service name into
    /// every one of them, so a prefix match would fail for every service.
    ///
    /// `Successfully started` / `Successfully stopped` are deliberately **not**
    /// here. They are corroboration only: brew prints them on the happy path,
    /// but their absence does not mean nothing happened, so making one the sole
    /// success test would turn every unfamiliar-but-fine run into a false
    /// report.
    private enum Marker {
        /// `Service \`X\` already started, use \`brew services restart X\` to
        /// restart.` — stdout, exit 0.
        static let alreadyStarted = "already started, use"
        /// `Warning: Service \`X\` is not started.` — stderr, exit 0.
        static let notStarted = "is not started"

        /// Both streams, because brew puts one marker on each.
        static func isNoChange(in log: [LogLine]) -> Bool {
            log.suffix(MutationOutcome.tailLength).contains { line in
                line.text.contains(alreadyStarted) || line.text.contains(notStarted)
            }
        }
    }

    // MARK: - Vector pieces

    /// Spelled as cases rather than literals so a typo is a compile error and
    /// the set of service verbs Cellar can issue is enumerable by reading.
    private enum Subcommand: String {
        case services
    }

    private enum Token: String {
        case start
        case run
        case stop
        case restart
    }

    private var token: Token {
        switch self {
        case .start: .start
        case .run: .run
        case .stop: .stop
        case .restart: .restart
        }
    }
}

/// Every control a service row exposes, as an enumerable surface.
///
/// Deliberately a list rather than a set of booleans, for the same reason
/// `ActivityItem.Control` and `HistoryRecord.Control` are: "both start-at-login
/// and run-once are present, separately invocable, and **no single control
/// chooses between them**" is then a claim a test can make about the whole
/// surface rather than an omission nobody wrote down (ruling #7182-3, SM5).
public enum ServiceRowControl: Sendable, Equatable, CaseIterable {
    /// `brew services start` — runs it now and registers it at login.
    case start
    /// `brew services run` — runs it now, and touches no login item.
    case run
    case stop
    case restart
    case copyCommand

    /// What the control says it does. The label states which of start and run
    /// it is, in words, because the difference is to the user's login items and
    /// a tooltip is not where that belongs.
    public var label: String {
        switch self {
        case .start: "Start at login"
        case .run: "Run once"
        case .stop: "Stop"
        case .restart: "Restart"
        case .copyCommand: "Copy command"
        }
    }

    /// Whether invoking this control registers the service to launch at login.
    ///
    /// Exactly one control does. Stated as a property so "nothing hidden touches
    /// login items" is checkable over `allCases` rather than by reading four
    /// call sites.
    public var isLoginRegistering: Bool { self == .start }

    /// The command this control submits, or `nil` for the one control that
    /// submits nothing.
    public func command(for target: ServiceTarget) -> ServiceCommand? {
        switch self {
        case .start: .start(target)
        case .run: .run(target)
        case .stop: .stop(target)
        case .restart: .restart(target)
        case .copyCommand: nil
        }
    }

    /// The controls a compact secondary surface offers for a service in this
    /// status.
    ///
    /// **Narrows the list; never collapses start-at-login and run-once into
    /// one.** A single switch whose "on" position starts a service would have to
    /// silently choose between registering a login item and not registering
    /// one, which SM5 forbids on every surface, not only on the roomy one.
    ///
    /// Exhaustive over all **eight** `ServiceStatus` cases with no `default:`
    /// arm, deliberately. `ServiceStatus` is not `CaseIterable` — it carries an
    /// `unrecognised(String)` for a status this build does not know — so a
    /// ninth status brew starts emitting has to be a compile-time decision
    /// here. A `default:` would hand it a control set by accident.
    ///
    /// The rule lives here rather than in the app target so "every reportable
    /// status is offered exactly one set, never both and never neither" is a
    /// claim over a returned array in the `swift test` inner loop.
    public static func compactControls(for status: ServiceStatus) -> [ServiceRowControl] {
        switch status {
        case .started: [.stop, .restart]
        case .none, .scheduled, .stopped, .error, .unknown, .other, .unrecognised: [.start, .run]
        }
    }
}
