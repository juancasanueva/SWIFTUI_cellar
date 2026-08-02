import Foundation

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
