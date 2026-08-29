import BrewProcess
import Foundation

/// Everything that can go wrong acquiring npm state.
///
/// Closed on purpose, for the same reason `InstalledInventoryError` is: the
/// store has to decide, for every case, whether the last good inventory
/// survives, and an open error type makes that decision impossible to review.
public enum NpmInventoryError: Error, Sendable, Equatable {
    /// There is no usable npm to ask. Guidance, not failure.
    case npmUnavailable
    /// npm ran and its exit could not be read as a result. `message` is the tail
    /// of its stderr, verbatim.
    case commandFailed(status: Int32, message: String)
    /// npm returned something that is not the documented document.
    case malformedPayload
    /// npm could not reach the registry. Its own case rather than a
    /// `commandFailed`, because being offline is a state a summary has to be
    /// able to *name*, and "npm exited 1" is not a sentence to show a user.
    case networkUnavailable
    /// The refresh was cancelled. Not a failure.
    case cancelled
}

/// The seam that produces npm's two read payloads.
///
/// Everything above this protocol is testable without a process: the store, the
/// coordinator and the decoders all see `Data` and nothing else.
public protocol NpmPayloadSourcing: Sendable {
    func installed(using environment: NpmEnvironment) async throws(NpmInventoryError) -> Data
    func outdated(using environment: NpmEnvironment) async throws(NpmInventoryError) -> Data
}

/// Turns one finished npm run into payload bytes, or into the reason there are
/// none.
///
/// A pure function over values a test can synthesise, which is what makes every
/// hostile shape reachable without a process. Its rules are **not** the brew
/// payload's, and the difference is the point.
///
/// Threat response — **exit-code semantics**. `InstalledPayload` treats any
/// non-zero exit as an error, and for brew that is right. For npm it would be
/// wrong twice over:
///
/// - `npm outdated -g --json` exits `1` whenever anything is outdated. That is
///   its ordinary success path, and refusing it would mean Cellar could only
///   ever report that nothing needs updating.
/// - `npm ls -g --json` exits `1` with a complete document when a global package
///   has an unsatisfied dependency (`ELSPROBLEMS`). Refusing it would blank the
///   whole list because one package's peer dependency is missing.
///
/// What does **not** relax: a non-zero exit whose stdout cannot be read is a
/// failure, never an empty result. An empty inventory presented as healthy reads
/// as "you have no global packages", and a user cannot see the exit code that
/// would tell them otherwise.
///
/// Threat response — **untrusted subprocess payload**: the document is read from
/// stdout only, at any interleaving, so a diagnostic npm writes to stderr can
/// never become part of what is decoded.
enum NpmPayload {
    /// How many trailing stderr lines are carried into the error.
    static let stderrTailLineCount = 12

    /// npm's own network error codes.
    ///
    /// npm's, and only npm's: brew's lock, sudo-prompt and untrusted-tap
    /// signatures classify nothing here, and a message produced from these must
    /// never mention Homebrew.
    static let networkCodes = ["ENOTFOUND", "ETIMEDOUT", "ECONNREFUSED", "EAI_AGAIN"]

    /// `npm ls -g --json --depth=0`: exit 0, or exit 1 with a readable document.
    static func installed(
        from lines: [LogLine],
        exit: BrewExit
    ) throws(NpmInventoryError) -> Data {
        try document(from: lines, exit: exit, acceptingExitOne: true, blankAtZero: nil)
    }

    /// `npm outdated -g --json`: exit 0 or 1, and blank stdout at exit 0 is the
    /// empty report rather than a missing answer.
    static func outdated(
        from lines: [LogLine],
        exit: BrewExit
    ) throws(NpmInventoryError) -> Data {
        try document(from: lines, exit: exit, acceptingExitOne: true, blankAtZero: "{}")
    }

    /// - Parameters:
    ///   - acceptingExitOne: whether exit `1` may still carry a result.
    ///   - blankAtZero: the document a *blank* stdout at exit `0` stands for, or
    ///     `nil` when blankness is malformed. Only `outdated` has a legitimate
    ///     empty answer; a blank `ls` is a listing that did not happen.
    private static func document(
        from lines: [LogLine],
        exit: BrewExit,
        acceptingExitOne: Bool,
        blankAtZero: String?
    ) throws(NpmInventoryError) -> Data {
        if exit.isCancelled { throw .cancelled }

        let accepted = exit.reason == .exited
            && (exit.status == 0 || (acceptingExitOne && exit.status == 1))
        guard accepted else { throw failure(from: lines, exit: exit) }

        let stdout = lines.lazy
            .filter { $0.stream == .stdout }
            .map(\.text)
            .joined(separator: "\n")
        let hasContent = stdout.contains { $0.isWhitespace == false }

        if hasContent == false {
            if exit.status == 0, let blankAtZero { return Data(blankAtZero.utf8) }
            // Blank stdout on a non-zero exit is the case that must never read
            // as an empty result: npm failed and told us why on stderr.
            if exit.status != 0 { throw failure(from: lines, exit: exit) }
            throw .malformedPayload
        }

        // A non-zero exit is only forgiven when stdout really parses. Otherwise
        // it is the failure it looks like — `ELSPROBLEMS` is accepted for its
        // document, not for its exit code.
        if exit.status != 0, JSONSerialization.isValidJSON(Data(stdout.utf8)) == false {
            throw failure(from: lines, exit: exit)
        }

        return Data(stdout.utf8)
    }

    /// The typed failure for a run that produced no result.
    ///
    /// Network first, because it is the one a summary has to be able to name.
    private static func failure(from lines: [LogLine], exit: BrewExit) -> NpmInventoryError {
        let tail = stderrTail(of: lines)
        if networkCodes.contains(where: tail.contains) { return .networkUnavailable }
        return .commandFailed(status: exit.status, message: tail)
    }

    private static func stderrTail(of lines: [LogLine]) -> String {
        lines
            .filter { $0.stream == .stderr }
            .suffix(stderrTailLineCount)
            .map(\.text)
            .joined(separator: "\n")
    }
}

extension JSONSerialization {
    /// Whether `data` is a JSON document at all.
    ///
    /// Only ever asked about a *non-zero* exit, to decide between "npm printed
    /// its answer and then complained" and "npm failed". Shape is checked by the
    /// decoders; this is the coarser question of whether there is anything for
    /// them to read.
    static func isValidJSON(_ data: Data) -> Bool {
        (try? jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }
}

/// The production source: one npm invocation per read.
///
/// Everything this type does is glue. It starts the invocation, drains its
/// output, waits for the terminal result, and hands both to `NpmPayload`.
///
/// It spawns through `ProcessLaunching` directly rather than through
/// `BrewRunner`, exactly as `DefaultNpmLocator` does for its two probes. The
/// runner's FIFO, cancel escalation and terminal retention exist for mutations;
/// a read needs none of them, and the runner cannot yet be handed an arbitrary
/// executable — that generalisation is the mutation slice's, and this source
/// moves onto it when it lands, without either of its rules changing.
public struct NpmPayloadSource: NpmPayloadSourcing {
    /// The only two npm invocations this capability makes for reading.
    ///
    /// Threat response — **argument composition**: compile-time constant argv
    /// vectors. There is no parameter, no interpolation and no string joining,
    /// so no package name from any payload can reach either of them.
    static let listArguments = ["ls", "-g", "--json", "--depth=0"]
    static let outdatedArguments = ["outdated", "-g", "--json"]

    private let launcher: any ProcessLaunching

    public init(launcher: any ProcessLaunching = SystemProcessLauncher()) {
        self.launcher = launcher
    }

    public func installed(
        using environment: NpmEnvironment
    ) async throws(NpmInventoryError) -> Data {
        let (lines, exit) = try await run(Self.listArguments, using: environment)
        return try NpmPayload.installed(from: lines, exit: exit)
    }

    public func outdated(
        using environment: NpmEnvironment
    ) async throws(NpmInventoryError) -> Data {
        let (lines, exit) = try await run(Self.outdatedArguments, using: environment)
        return try NpmPayload.outdated(from: lines, exit: exit)
    }

    private func run(
        _ arguments: [String],
        using environment: NpmEnvironment
    ) async throws(NpmInventoryError) -> (lines: [LogLine], exit: BrewExit) {
        let process: any LaunchedProcess
        do {
            process = try launcher.launch(
                ProcessSpec(
                    executableURL: environment.executableURL,
                    arguments: arguments,
                    environment: environment.processEnvironment()
                )
            )
        } catch {
            // Detection said there was an npm here and the spawn disagrees. That
            // is guidance, not a failure the user can act on differently.
            throw .npmUnavailable
        }

        return await ProcessOutputCollector.drain(process)
    }
}
