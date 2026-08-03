import BrewProcess
import Foundation

/// A service name, proven safe to put in argv.
///
/// The services detail probe is the **only parameterised read argv** in the
/// codebase, so the guarantee `PackageTarget` gives the mutating commands has
/// to hold here too — and it holds the same way, through the one
/// `MutationName.isSafe` gate. An unvalidated services read is unrepresentable
/// rather than merely discouraged.
///
/// A service is its own entity: this is deliberately **not** a `PackageID`, and
/// nothing derives one from the other (service-management SM12).
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

/// The seam that produces one services list payload.
public protocol ServicesPayloadSourcing: Sendable {
    func payload(using installation: BrewInstallation) async throws(ServicesError) -> Data
}

/// The seam that produces one service's detail payload.
public protocol ServiceDetailPayloadSourcing: Sendable {
    func payload(
        using installation: BrewInstallation,
        naming target: ServiceTarget
    ) async throws(ServicesError) -> Data
}

/// The production list source: one `brew services list --json` run.
///
/// Glue only, exactly like `BrewInfoPayloadSource`: start, drain, wait, hand
/// both to the pure payload function.
public struct ServicesListPayloadSource: ServicesPayloadSourcing {
    /// Threat response — **argument composition**: a compile-time constant argv
    /// vector. There is no parameter, no interpolation and no string joining.
    /// `.read` because it changes nothing, which is also what keeps a 5-second
    /// poll out of the mutation gate.
    static let command = BrewCommand.read(["services", "list", "--json"])

    private let launcher: any ProcessLaunching

    public init(launcher: any ProcessLaunching = SystemProcessLauncher()) {
        self.launcher = launcher
    }

    public func payload(
        using installation: BrewInstallation
    ) async throws(ServicesError) -> Data {
        try await ServicesRun.payload(
            of: Self.command,
            using: installation,
            launcher: launcher
        )
    }
}

/// The production detail source: one `brew services info --json <name>` run.
public struct ServiceInfoPayloadSource: ServiceDetailPayloadSourcing {
    /// The fixed head of the vector. The name is appended as its own, final
    /// element — never interpolated into one of these — and `--all` is not one
    /// of them, so a detail probe cannot widen into a probe of everything.
    static let head = ["services", "info", "--json"]

    private let launcher: any ProcessLaunching

    public init(launcher: any ProcessLaunching = SystemProcessLauncher()) {
        self.launcher = launcher
    }

    static func command(naming target: ServiceTarget) -> BrewCommand {
        .read(head + [target.name])
    }

    public func payload(
        using installation: BrewInstallation,
        naming target: ServiceTarget
    ) async throws(ServicesError) -> Data {
        try await ServicesRun.payload(
            of: Self.command(naming: target),
            using: installation,
            launcher: launcher
        )
    }
}

/// One `brew` run, reduced to bytes or to the reason there are none.
///
/// Shared by both sources because the twenty lines of glue are identical and
/// duplicating them would give the two probes two chances to drift apart on
/// draining order.
enum ServicesRun {
    static func payload(
        of command: BrewCommand,
        using installation: BrewInstallation,
        launcher: any ProcessLaunching
    ) async throws(ServicesError) -> Data {
        let runner = BrewRunner(installation: installation, launcher: launcher)

        let operation: BrewOperation
        do {
            operation = try await runner.start(command)
        } catch {
            throw acquisitionFailure(error)
        }

        // Draining before asking for the exit is the runner's ordering
        // contract: the terminal result is never delivered before the output is
        // complete.
        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }

        return try ServicesPayload.payload(from: lines, exit: await operation.exit())
    }

    private static func acquisitionFailure(_ error: BrewProcessError) -> ServicesError {
        switch error {
        case .executableUnavailable:
            .brewUnavailable
        case .launchFailed(_, let code):
            .commandFailed(status: code, message: String(describing: error))
        case .cancelledUnresponsive:
            .cancelled
        }
    }
}

/// Turns one finished services run into payload bytes, or into the reason there
/// are none.
///
/// Threat response — **untrusted subprocess payload**. A pure function over
/// values a test can synthesise, so every hostile shape is reachable without a
/// process. The three rules are `InstalledPayload`'s, deliberately verbatim
/// rather than re-derived (design D7):
///
/// - a non-zero exit is an **error**, never an empty list — brew failing while
///   printing `[]` must not read as "you have no services";
/// - stderr never enters the document, at any position, so a warning
///   interleaved into the middle of the JSON cannot corrupt it;
/// - an empty or blank document is malformed, for the same reason as the first.
enum ServicesPayload {
    /// How many trailing stderr lines are carried into the error. brew writes
    /// its diagnosis last and its progress noise first.
    static let stderrTailLineCount = 12

    static func payload(
        from lines: [LogLine],
        exit: BrewExit
    ) throws(ServicesError) -> Data {
        if exit.isCancelled { throw .cancelled }
        guard exit.isSuccess else {
            throw .commandFailed(status: exit.status, message: stderrTail(of: lines))
        }

        let document = lines.lazy
            .filter { $0.stream == .stdout }
            .map(\.text)
            .joined(separator: "\n")

        guard document.contains(where: { !$0.isWhitespace }) else {
            throw .malformedPayload
        }
        return Data(document.utf8)
    }

    private static func stderrTail(of lines: [LogLine]) -> String {
        lines
            .filter { $0.stream == .stderr }
            .suffix(stderrTailLineCount)
            .map(\.text)
            .joined(separator: "\n")
    }
}
