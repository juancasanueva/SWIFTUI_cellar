import BrewProcess
import Catalog

// MARK: - Threat response: subprocess argument composition, generalized
//
// This file is what lets a second capability put commands on the shared queue.
// The three properties `MutationCommand.swift` establishes for package
// mutations are preserved for **every** conformer, and preserved the same way —
// by construction rather than by discipline (design D1):
//
// 1. **argv, never a string.** `brewCommand` hands `arguments` to
//    `BrewCommand.mutate` element by element. Nothing joins, quotes,
//    interpolates or shells out, at any point on the path.
// 2. **Names are refused at construction.** The protocol takes an already-built
//    argv, so validation happens in the conformer's own failable factory. The
//    structural rule the suite enforces: *a conformer's `arguments` may contain
//    only literal verb/flag enum raw values plus tokens taken from a validated
//    wrapper* — `MutationName.isSafe` stays the single gate for every family.
// 3. **`displayCommand` is one-way.** It renders argv for a human to read or
//    paste. Nothing anywhere parses a command string back into arguments, and
//    the erased value below carries no case payload that could be recovered.

/// The state domains a command's terminal outcome invalidates.
///
/// This solves **scoped invalidation** and nothing else. A services toggle
/// changes nothing in the installed set, so it must not pay for a
/// `brew info --installed --json=v2` probe it could not learn anything from —
/// 1.27 s and 663 KB, per toggle, for a guaranteed no-op.
///
/// An `OptionSet` rather than an enum because a command may genuinely invalidate
/// more than one domain, and because "the intersection of what ran and what is
/// being watched" is then a one-line, total operation rather than a switch that
/// has to be kept exhaustive by hand (design D2).
public struct InvalidationScope: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// What `brew info --installed --json=v2` answers for.
    public static let installedInventory = InvalidationScope(rawValue: 1 << 0)
    /// What `brew services list --json` answers for.
    public static let services = InvalidationScope(rawValue: 1 << 1)

    // `1 << 2` taps (M3-2) and `1 << 3` disk usage (M3-3) are **reserved by this
    // comment and deliberately not declared**: an undeclared bit cannot be
    // begun, ended or asserted over, so neither milestone inherits a domain that
    // silently does nothing.
}

/// Everything the mutation spine needs from a command, whichever capability owns
/// it.
///
/// `Sendable` **only**. An `Equatable` or `Hashable` `Self`-requirement would
/// make the protocol unusable as a stored property — which is exactly what
/// `ActivityItem` and `ConfirmationRequest` need it to be — and would break
/// `ConfirmationRequest: Equatable` and the four shipped assertions that rest on
/// it. Equality lives on `AnyBrewMutation` instead, where it is equality of
/// *what will run* (design D1).
///
/// Taken by **generic** parameters throughout the spine rather than as an
/// existential, so every app-target call site that passes a `MutationCommand`
/// compiles unchanged and no boxing is introduced on the hot path.
public protocol BrewMutating: Sendable {
    /// The argv vector, excluding the `brew` executable itself.
    var arguments: [String] { get }
    /// The verb this command is recorded and searched under
    /// (installation-history IH1, IH5).
    var verb: String { get }
    /// The package this command acts on — `nil` for every non-package family,
    /// and for the grouped `upgradeAll`.
    var packageID: PackageID? { get }
    /// Whether this command destroys something and must be agreed first.
    var requiresConfirmation: Bool { get }
    /// The state domains one terminal outcome of this command invalidates.
    var invalidates: InvalidationScope { get }

    /// Decides the outcome from the terminal facts and the output.
    ///
    /// A protocol requirement with a default rather than a free function, so a
    /// family whose exit code cannot separate its own outcomes can override it
    /// **for itself** — and only for itself. That is what keeps `brew services`'
    /// stdout marker pass from ever reaching an `install` (design D4).
    func classify(exit: BrewExit, fault: BrewProcessError?, log: [LogLine]) -> MutationOutcome
}

extension BrewMutating {
    /// The command as a human reads it — and as they can paste it.
    ///
    /// Display only. Nothing parses this back into argv, which is what makes
    /// the confirmation sheet and the copy affordance incapable of changing
    /// what runs.
    public var displayCommand: String {
        "brew " + arguments.joined(separator: " ")
    }

    /// The runnable form, always serialized as a mutation — so a new family
    /// inherits `brew-execution` BE5 (serialized mutations, concurrent reads)
    /// without restating it.
    public var brewCommand: BrewCommand {
        .mutate(arguments)
    }

    /// Today's classification logic, verbatim and unmoved: a fault, a
    /// cancellation and a zero exit are all decided before a single byte of
    /// subprocess output is examined, and prose is read from **stderr only**.
    public func classify(
        exit: BrewExit,
        fault: BrewProcessError?,
        log: [LogLine]
    ) -> MutationOutcome {
        MutationOutcome.classify(exit: exit, fault: fault, log: log)
    }
}

/// One mutation, reduced to the projections the spine reads.
///
/// Held by `ActivityItem` and `ConfirmationRequest`, which need a *stored*
/// command and therefore cannot hold a generic one. Two consequences, both
/// deliberate:
///
/// - **`Equatable` is restored for free**, so `ConfirmationRequest: Equatable`
///   and its four shipped assertions keep working across the generalisation.
/// - **Nothing can be parsed back out of it.** There is no case payload to
///   recover and no reference to the command that produced it, so the shipped
///   "nothing is parsed back out of a command" property is strengthened rather
///   than weakened: two commands that would run the same argv erase to the same
///   value, and neither can be widened back into something that runs anything
///   else.
///
/// It deliberately carries **no classifier**. Classification always runs on the
/// concrete command at the terminal — `OperationCenter.run` is generic and holds
/// it — so the erasure is never on that path. Conforming to `BrewMutating` with
/// the protocol default is therefore honest rather than lossy: the erased value
/// is asked for its projections, never for a verdict.
public struct AnyBrewMutation: BrewMutating, Sendable, Equatable, Hashable {
    public let arguments: [String]
    public let verb: String
    public let packageID: PackageID?
    public let requiresConfirmation: Bool
    public let invalidates: InvalidationScope

    public init(_ command: some BrewMutating) {
        arguments = command.arguments
        verb = command.verb
        packageID = command.packageID
        requiresConfirmation = command.requiresConfirmation
        invalidates = command.invalidates
    }
}

/// The six package commands, on the shared spine.
///
/// Everything the protocol asks for is already a computed property on the enum;
/// the only thing this adds is the scope declaration. That is the whole of
/// "another family enters through a shared abstraction rather than as a seventh
/// case" (package-mutation PM1).
extension MutationCommand: BrewMutating {
    /// Every package mutation changes what is installed — including `pin` and
    /// `unpin`, which change the record `brew info --installed` publishes.
    public var invalidates: InvalidationScope { .installedInventory }
}
