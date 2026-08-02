import Foundation

/// Everything `BrewRunner` tracks about one submitted operation.
///
/// It lives beside the handle rather than inside the actor purely so
/// `BrewRunner.swift` stays under the 400-line limit (design D11). The
/// dictionary that holds these records stays `private` to the actor, so the
/// projection is still derived in the same file as the state it describes.
struct OperationRecord {
    /// The operation's stable identity, mirrored here so the record can project
    /// itself without the dictionary key being passed back in.
    let id: UUID
    /// The argv this operation was submitted with, so the projection can carry
    /// it verbatim without the caller having to remember it.
    let command: BrewCommand
    /// Submission order, so a `[UUID: …]` dictionary can be rendered in the
    /// order brew will actually run things.
    let ordinal: Int
    /// Held for the operation's lifetime on purpose: an `AsyncStream` that
    /// nobody retains terminates as `.cancelled`, which would silently cancel an
    /// operation whose caller only cares about `exit()`.
    let lines: AsyncStream<LogLine>
    let continuation: AsyncStream<LogLine>.Continuation
    var process: (any LaunchedProcess)?
    /// Invariant I3: the pump is unstructured but owned by this record and
    /// cancelled when the operation ends.
    var pump: Task<Void, Never>?
    /// Completes only once the operation has a terminal result.
    var completion: Task<Void, Never>?
    var resolvedExit: BrewExit?
    var fault: BrewProcessError?
    /// Set before a signal is delivered, so the terminal result can be reported
    /// as cancelled rather than as a plain signal death.
    var cancellationSignal: Int32?
    var isCancelling = false

    /// The read-only view of this record.
    ///
    /// The phase is **derived** here and stored nowhere: `resolvedExit` answers
    /// "terminal?", `process` answers "spawned?", and the two together are the
    /// whole truth. Storing a third field would let the projection drift from
    /// the state it describes (design D3).
    var projection: OperationSnapshot {
        let phase: OperationSnapshot.Phase = if let resolvedExit {
            .terminal(resolvedExit, fault: fault)
        } else if process != nil {
            .running
        } else {
            .pending
        }
        return OperationSnapshot(id: id, command: command, phase: phase)
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

    /// An out-of-band fault, if one occurred. `nil` for every normal run.
    public func fault() async -> BrewProcessError? {
        await runner.fault(of: id)
    }

    /// Stops the operation, escalating `SIGINT` → `SIGTERM`.
    public func cancel() async {
        await runner.cancel(id)
    }
}

extension BrewRunner {
    /// Maps a spawn fault onto the narrow `BrewProcessError` taxonomy.
    static func mapLaunchFailure(
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
