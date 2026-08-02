import BrewProcess
import Foundation

/// Everything that can go wrong acquiring an installed snapshot.
///
/// Closed on purpose: the store has to decide, for every case, whether the last
/// good inventory survives. An open error type makes that decision impossible to
/// review (design D6).
public enum InstalledInventoryError: Error, Sendable, Equatable {
    /// There is no usable `brew` to ask. Guidance, not failure.
    case brewUnavailable
    /// `brew` ran and returned non-zero. `message` is the tail of its stderr.
    case commandFailed(status: Int32, message: String)
    /// `brew` returned something that is not the documented payload.
    case malformedPayload
    /// The refresh was cancelled. Not a failure (`BrewProcess` D3).
    case cancelled
}

/// The seam that produces one installed snapshot payload.
///
/// Everything above this protocol is testable without a process: the store, the
/// coordinator and the decoder all see `Data` and nothing else.
public protocol InstalledPayloadSourcing: Sendable {
    func payload(
        using installation: BrewInstallation
    ) async throws(InstalledInventoryError) -> Data
}

/// Turns one finished `brew` run into payload bytes, or into the reason there
/// are none.
///
/// Threat response — **untrusted subprocess payload**. This is a pure function
/// over values that a test can synthesise, which is what makes every hostile
/// shape reachable without a process: a non-zero exit, an empty document,
/// stderr interleaved into the middle of the JSON. The rules it encodes:
///
/// - a non-zero exit is an **error**, never an empty inventory — brew failing
///   while printing `{"formulae":[],"casks":[]}` must not read as "the user
///   uninstalled everything";
/// - stderr never enters the document, at any position;
/// - an empty or blank document is malformed, for the same reason.
enum InstalledPayload {
    /// How many trailing stderr lines are carried into the error.
    ///
    /// brew writes its diagnosis last and its progress noise first, so the tail
    /// is where the reason lives.
    static let stderrTailLineCount = 12

    static func payload(
        from lines: [LogLine],
        exit: BrewExit
    ) throws(InstalledInventoryError) -> Data {
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

/// The production source: one `brew info --installed --json=v2` run.
///
/// Everything this type does is glue. It starts the invocation, drains its
/// output, waits for the terminal result, and hands both to
/// `InstalledPayload.payload(from:exit:)`. Keeping it this thin is what lets the
/// interesting decisions be tested without a process at all (design D2).
public struct BrewInfoPayloadSource: InstalledPayloadSourcing {
    /// The only `brew` invocation this capability makes.
    ///
    /// Threat response — **argument composition**: a compile-time constant argv
    /// vector. There is no parameter, no interpolation and no string joining, so
    /// no package name, search query or catalog record can reach it. `.read`
    /// because it changes nothing, which also keeps a re-snapshot out of the
    /// mutation gate.
    static let command = BrewCommand.read(["info", "--installed", "--json=v2"])

    private let launcher: any ProcessLaunching

    public init(launcher: any ProcessLaunching = SystemProcessLauncher()) {
        self.launcher = launcher
    }

    public func payload(
        using installation: BrewInstallation
    ) async throws(InstalledInventoryError) -> Data {
        let runner = BrewRunner(installation: installation, launcher: launcher)

        let operation: BrewOperation
        do {
            operation = try await runner.start(Self.command)
        } catch {
            throw Self.acquisitionFailure(error)
        }

        // Draining before asking for the exit is the runner's ordering contract:
        // the terminal result is never delivered before the output is complete.
        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }

        return try InstalledPayload.payload(from: lines, exit: await operation.exit())
    }

    private static func acquisitionFailure(
        _ error: BrewProcessError
    ) -> InstalledInventoryError {
        switch error {
        case .executableUnavailable:
            // Detection said there was a brew here and the spawn disagrees. That
            // is guidance, not a failure the user can act on differently.
            .brewUnavailable
        case .launchFailed(_, let code):
            .commandFailed(status: code, message: String(describing: error))
        case .cancelledUnresponsive:
            .cancelled
        }
    }
}
