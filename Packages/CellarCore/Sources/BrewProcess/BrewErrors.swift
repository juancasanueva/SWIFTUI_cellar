import Foundation

/// A fault that prevented an operation from producing a `BrewExit`.
///
/// Deliberately narrow: a non-zero exit status is a result, not an error (D3).
/// Only spawn faults and an unresponsive cancellation reach this type.
public enum BrewProcessError: Error, Sendable, Equatable {
    /// The executable could not be found or is not runnable (ENOENT / EACCES).
    case executableUnavailable(URL)
    /// The spawn itself failed with a POSIX error code.
    case launchFailed(URL, code: Int32)
    /// The process ignored both SIGINT and SIGTERM within the cancellation
    /// budget. Cellar never escalates to SIGKILL (D4), so this surfaces to the
    /// caller instead.
    case cancelledUnresponsive(after: Duration)
}

/// Why a candidate `brew` executable was rejected during detection.
///
/// Exactly one reason is reported per failed validation; the three checks run
/// in order (executable → genuine Homebrew → version floor).
public enum BrewValidationError: Error, Sendable, Equatable {
    /// The path exists but is not an executable regular file.
    case notExecutable(URL)
    /// The binary ran but its `--version` output is not Homebrew's.
    case notHomebrew(URL, output: String)
    /// The binary is Homebrew but older than the supported floor.
    case versionTooOld(BrewVersion, minimum: BrewVersion)
    /// The binary could not be probed at all.
    case probeFailed(URL, message: String)
}
