/// A `brew` invocation expressed as an argv vector plus its serialization kind.
///
/// Threat response — argument composition: `arguments` is argv and only argv.
/// It is handed to the process seam element-by-element, so a value containing a
/// space, `;`, or `$(...)` stays one literal argument. `BrewProcess` never
/// builds a command line string and never routes through `/bin/sh -c`.
public struct BrewCommand: Sendable, Equatable {
    /// Whether the command may change Homebrew state.
    ///
    /// `.read` commands bypass the mutation gate; `.mutate` commands run FIFO,
    /// one at a time (design decision D5).
    public enum Kind: Sendable, Equatable {
        case read
        case mutate
    }

    /// The argv vector, excluding the `brew` executable itself.
    public let arguments: [String]

    /// The serialization kind.
    public let kind: Kind

    public init(arguments: [String], kind: Kind) {
        self.arguments = arguments
        self.kind = kind
    }

    /// A read-only query that may run concurrently with an in-flight mutation.
    public static func read(_ arguments: [String]) -> BrewCommand {
        BrewCommand(arguments: arguments, kind: .read)
    }

    /// A state-changing command that must run alone, in submission order.
    public static func mutate(_ arguments: [String]) -> BrewCommand {
        BrewCommand(arguments: arguments, kind: .mutate)
    }
}
