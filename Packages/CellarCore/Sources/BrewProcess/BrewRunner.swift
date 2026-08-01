import Foundation

/// Runs `brew` commands and publishes their output as it arrives.
///
/// The runner owns process lifetime and stream plumbing; it deliberately owns
/// no parsing or presentation. Every subprocess reaches the outside world
/// through the injected `ProcessLaunching` seam, so the whole actor is testable
/// without spawning anything.
public actor BrewRunner {
    private struct OperationRecord {
        let process: any LaunchedProcess
        /// Invariant I3: the pump is unstructured but owned by this record and
        /// cancelled when the operation ends.
        let pump: Task<Void, Never>
        var resolvedExit: BrewExit?
    }

    private let installation: BrewInstallation
    private let launcher: any ProcessLaunching
    private var operations: [UUID: OperationRecord] = [:]

    public init(
        installation: BrewInstallation,
        launcher: any ProcessLaunching = SystemProcessLauncher()
    ) {
        self.installation = installation
        self.launcher = launcher
    }

    /// How many operations the runner is still tracking. Test-facing.
    var activeOperationCount: Int { operations.count }

    /// Spawns `command` and returns a handle to its output.
    public func start(_ command: BrewCommand) async throws(BrewProcessError) -> BrewOperation {
        let spec = ProcessSpec(
            executableURL: installation.executableURL,
            arguments: command.arguments,
            environment: BrewEnvironment.current()
        )

        let process: any LaunchedProcess
        do {
            process = try launcher.launch(spec)
        } catch {
            // Nothing was recorded before the launch attempt, so a failure
            // leaves no half-built operation behind.
            throw Self.mapLaunchFailure(error, executableURL: installation.executableURL)
        }

        let (lines, continuation) = AsyncStream<LogLine>.makeStream()
        let pump = Self.startPump(reading: process, into: continuation)

        let id = UUID()
        operations[id] = OperationRecord(process: process, pump: pump)

        return BrewOperation(id: id, lines: lines, runner: self)
    }

    /// The terminal result of `id`, once every line it produced is observable.
    ///
    /// Never throws: a cancelled run is a `BrewExit.Reason`, not a failure (D3).
    func exit(of id: UUID) async -> BrewExit {
        guard let record = operations[id] else {
            return BrewExit(status: 0, reason: .exited)
        }
        if let resolved = record.resolvedExit { return resolved }

        // Awaiting the pump first is what guarantees the ordering contract:
        // the result is never delivered before the output is observable.
        await record.pump.value
        let exit = await record.process.waitForTermination()

        operations[id]?.resolvedExit = exit
        return exit
    }

    /// Drains raw chunks into whole, tagged, sequenced lines (design D2).
    private static func startPump(
        reading process: any LaunchedProcess,
        into continuation: AsyncStream<LogLine>.Continuation
    ) -> Task<Void, Never> {
        Task {
            var splitter = LineSplitter()
            for await chunk in process.output {
                for line in splitter.consume(chunk) {
                    continuation.yield(line)
                }
            }
            for line in splitter.flush() {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }

    /// Maps a spawn fault onto the narrow `BrewProcessError` taxonomy.
    private static func mapLaunchFailure(
        _ error: any Error,
        executableURL: URL
    ) -> BrewProcessError {
        if let brewError = error as? BrewProcessError { return brewError }

        if let posix = error as? POSIXError {
            switch posix.code {
            case .ENOENT, .EACCES, .EPERM, .ENOEXEC:
                return .executableUnavailable(executableURL)
            default:
                return .launchFailed(executableURL, code: posix.code.rawValue)
            }
        }

        let cocoa = error as NSError
        if cocoa.domain == NSCocoaErrorDomain,
           cocoa.code == CocoaError.fileNoSuchFile.rawValue
               || cocoa.code == CocoaError.fileReadNoPermission.rawValue {
            return .executableUnavailable(executableURL)
        }

        return .launchFailed(executableURL, code: Int32(truncatingIfNeeded: cocoa.code))
    }
}

/// A handle to one running `brew` invocation.
public struct BrewOperation: Sendable, Identifiable {
    public let id: UUID
    /// Whole lines, in the order they were read.
    public let lines: AsyncStream<LogLine>

    private let runner: BrewRunner

    init(id: UUID, lines: AsyncStream<LogLine>, runner: BrewRunner) {
        self.id = id
        self.lines = lines
        self.runner = runner
    }

    /// The terminal result, available only after every line is observable.
    public func exit() async -> BrewExit {
        await runner.exit(of: id)
    }
}
