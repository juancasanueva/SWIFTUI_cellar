import Foundation

/// Everything needed to spawn one subprocess.
///
/// `arguments` is an argv vector. Nothing in `BrewProcess` ever joins it into a
/// command line or hands it to a shell.
public struct ProcessSpec: Sendable, Equatable {
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]

    public init(executableURL: URL, arguments: [String], environment: [String: String]) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
    }
}

/// A run of bytes read from one of the process's two output pipes, in arrival
/// order. Chunk boundaries are arbitrary: a line may span several chunks and a
/// chunk may contain several lines.
public enum OutputChunk: Sendable, Equatable {
    case stdout(Data)
    case stderr(Data)
}

/// The signals Cellar is allowed to deliver.
///
/// SIGKILL is deliberately absent: killing brew outright leaves a stale lock
/// and a half-linked keg (design decision D4).
public enum ProcessSignal: Sendable, Equatable {
    /// `SIGINT` — ask brew to stop cooperatively.
    case interrupt
    /// `SIGTERM` — escalation after the interrupt grace period.
    case terminate

    /// The POSIX signal number delivered for this case.
    public var posixValue: Int32 {
        switch self {
        case .interrupt: SIGINT
        case .terminate: SIGTERM
        }
    }
}

/// The seam that makes `BrewRunner` testable without spawning anything.
public protocol ProcessLaunching: Sendable {
    func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess
}

/// A spawned process, observed as a byte stream plus a termination result.
public protocol LaunchedProcess: Sendable, AnyObject {
    /// Raw output in arrival order. Finishes exactly once, after both pipes hit
    /// EOF and the process has been reaped (invariant I1).
    var output: AsyncStream<OutputChunk> { get }

    /// Delivers `signal` to the process. Throwing means the signal could not be
    /// delivered at all; a process that simply ignores it does not throw.
    func send(_ signal: ProcessSignal) throws

    /// Resolves once the process has terminated and been reaped.
    func waitForTermination() async -> BrewExit
}
