import Foundation

/// Everything decided about an operation at the moment it is submitted.
///
/// It exists so the two paths out of `start(_:)` — spawn now, or join the FIFO
/// gate — take one value rather than six positional arguments each. Both build
/// their `OperationRecord` from it, so the two paths cannot drift apart in what
/// they record.
struct Submission {
    let id: UUID
    let command: BrewCommand
    let ordinal: Int
    let lines: AsyncStream<LogLine>
    let continuation: AsyncStream<LogLine>.Continuation
    let authorizer: (any MutationLaunchAuthorizing)?

    func record(
        process: (any LaunchedProcess)? = nil,
        pump: Task<Void, Never>? = nil
    ) -> OperationRecord {
        OperationRecord(
            id: id,
            command: command,
            ordinal: ordinal,
            lines: lines,
            continuation: continuation,
            authorizer: authorizer,
            process: process,
            pump: pump
        )
    }
}

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
    /// Held until the operation is terminal on purpose: an `AsyncStream` that
    /// nobody retains terminates as `.cancelled`, which would silently cancel an
    /// operation whose caller only cares about `exit()`. Released by compaction
    /// (R2), by which point the continuation has already finished.
    var lines: AsyncStream<LogLine>?
    var continuation: AsyncStream<LogLine>.Continuation?
    let authorizer: (any MutationLaunchAuthorizing)?
    var process: (any LaunchedProcess)?
    /// Invariant I3: the pump is unstructured but owned by this record and
    /// cancelled when the operation ends.
    var pump: Task<Void, Never>?
    /// Completes only once the operation has a terminal result.
    var completion: Task<Void, Never>?
    var terminal: OperationTerminal?
    var pendingFault: BrewProcessError?
    /// Set before a signal is delivered, so the terminal result can be reported
    /// as cancelled rather than as a plain signal death.
    var cancellationSignal: Int32?
    var isCancelling = false

    // MARK: - Retention (design D6, brew-execution BE1)
    //
    // Three ordered rules. Their whole point is that the guarantee "eviction
    // cannot break `exit(of:)` for an operation still being awaited" is
    // **structural** rather than probabilistic:
    //
    //   R1  A record that is not terminal is never touched.
    //   R2  On terminal ∧ drained the record is *compacted* — `process`, `pump`,
    //       `completion`, `continuation` and `lines` are released. `id`,
    //       `command`, `ordinal`, `resolvedExit` and `fault` survive (about a
    //       hundred bytes), so it stays enumerable and answers exactly.
    //   R3  A compacted record is *removed* only once its `BrewOperation` handle
    //       has been deallocated. Released-and-compacted records are then capped
    //       oldest-ordinal-first, so the bound is `live handles + the cap`.
    //
    // Rejected: an explicit `runner.retire(id)` call — correctness would depend
    // on every consumer (`OperationCenter` *and* `InstalledPayloadSource`)
    // remembering to make it, and a consumer added later would leak silently
    // rather than fail loudly. Rejected: a plain LRU over terminal records — it
    // evicts by count regardless of who still holds a handle, which is exactly
    // the timing bet BE1 forbids.

    /// True once R2 has released this record's execution resources. The record
    /// itself stays: `id`, `command`, `ordinal`, `resolvedExit` and `fault` are
    /// about a hundred bytes and are what `exit(of:)`, `fault(of:)` and the
    /// projection are made of.
    var isCompacted = false

    /// True once the `BrewOperation` handle for this operation has been
    /// deallocated, so no caller can still ask about it. Removal (R3) is gated
    /// on this rather than on elapsed time or on a count of terminals.
    var isReleased = false

    /// Whether the record still pins a process, a task or a stream.
    ///
    /// The claim R2 makes, in one place, so the test asserting it and the code
    /// performing it cannot describe different sets of fields.
    var holdsExecutionResources: Bool {
        process != nil || pump != nil || completion != nil || continuation != nil || lines != nil
    }

    /// The read-only view of this record.
    ///
    /// The phase is **derived** here and stored nowhere: `resolvedExit` answers
    /// "terminal?", `process` answers "spawned?", and the two together are the
    /// whole truth. Storing a third field would let the projection drift from
    /// the state it describes (design D3).
    var projection: OperationSnapshot {
        let phase: OperationSnapshot.Phase = if let terminal {
            switch terminal {
            case .process(let exit, let fault):
                .terminal(exit, fault: fault)
            case .authorizationDenied(let denial):
                .authorizationDenied(denial)
            }
        } else if process != nil {
            .running
        } else {
            .pending
        }
        return OperationSnapshot(id: id, command: command, phase: phase)
    }
}

enum OperationTerminal {
    case process(BrewExit, fault: BrewProcessError?)
    case authorizationDenied(MutationLaunchDenial)
}

/// A handle to one running `brew` invocation.
///
/// A **class**, not a struct, and that is the whole of design D6's release rule:
/// the runner may drop a terminal record only once nobody can still ask about
/// it, and "nobody" is exactly "this handle is gone". `deinit` hands the id back.
/// Expressed as ownership, the guarantee is structural; expressed as a count or
/// a timer, it would be a bet that the last `exit()` already happened.
///
/// Every stored property is immutable and `Sendable`, so the type keeps the
/// `Sendable` conformance its struct form had and callers see no change.
public final class BrewOperation: Sendable, Identifiable {
    public let id: UUID
    /// Whole lines, in the order they were read.
    public let lines: AsyncStream<LogLine>

    private let runner: BrewRunner

    init(id: UUID, lines: AsyncStream<LogLine>, runner: BrewRunner) {
        self.id = id
        self.lines = lines
        self.runner = runner
    }

    deinit {
        // `self` must not escape a `deinit`, so the two values the runner needs
        // are copied out first. Releasing is advisory: the runner decides what,
        // if anything, becomes removable as a result (R3).
        let runner = runner
        let id = id
        Task { await runner.release(id) }
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

/// A handle whose terminal can be either a process result or a pre-spawn denial.
public final class AuthorizedMutationOperation: Sendable, Identifiable {
    public let id: UUID
    public let lines: AsyncStream<LogLine>

    private let runner: BrewRunner

    init(id: UUID, lines: AsyncStream<LogLine>, runner: BrewRunner) {
        self.id = id
        self.lines = lines
        self.runner = runner
    }

    deinit {
        let runner = runner
        let id = id
        Task { await runner.release(id) }
    }

    public func terminal() async -> AuthorizedMutationTerminal {
        await runner.authorizedTerminal(of: id)
    }

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
