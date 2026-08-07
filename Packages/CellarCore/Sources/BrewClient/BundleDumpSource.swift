import BrewProcess
import Catalog
import Foundation

/// Everything a dump can fail as.
///
/// The `CleanupPreviewError` shape — the only shipped payload error that keeps
/// **both** raw streams. A non-zero exit is never reported as a successful
/// empty document, and its stdout and stderr are preserved verbatim so a user
/// can be told what brew actually said (`brewfile-management` BF8).
public enum BundleDumpError: Error, Sendable, Equatable {
    case unavailable(InstalledAbsence)
    case commandFailed(status: Int32, rawStdout: Data, rawStderr: Data)
    case launchFailed(BrewProcessError)
    case cancelled(rawStdout: Data, rawStderr: Data)
    /// The run exited `0` but the file it was pointed at could not be read.
    /// A typed outcome rather than an empty document, because "brew wrote
    /// nothing" and "we could not read what brew wrote" are different failures.
    case documentUnreadable

    public var isCancellation: Bool { if case .cancelled = self { true } else { false } }
}

/// One successful dump.
public struct BundleDumpResult: Sendable, Equatable {
    /// The bytes brew wrote at `--file`, verbatim.
    public let document: Data
    /// Diagnostics. Never part of the document, at any position.
    public let rawStderr: Data

    public init(document: Data, rawStderr: Data) {
        self.document = document
        self.rawStderr = rawStderr
    }
}

public protocol BundleDumpSourcing: Sendable {
    func dump(for detection: BrewDetectionState) async throws(BundleDumpError) -> BundleDumpResult
}

/// Runs `brew bundle dump` against a path Cellar created, and cleans up after
/// itself on every path out.
///
/// Mirrors `CleanupPreviewSource`: a `nonisolated Sendable` struct over
/// `any ProcessLaunching`, with `withTaskCancellationHandler` delivering the
/// interrupt. The one thing it adds is the temporary lifecycle, and that is the
/// whole of threat row TM3:
///
/// - `--file` is a **fresh** `<tmp>/cellar-brewfile/<UUID>/Brewfile` per export,
///   so `--force` can never overwrite a file the user owns.
/// - The directory is created before brew is asked for anything, and removed in
///   a `defer` — one call site, so success, failure and cancellation cannot
///   drift apart.
/// - The document is read from the **file**. A successful dump writes nothing to
///   stdout at all (the capture records 0 bytes), so a source reading stdout
///   would publish an empty Brewfile and call it success.
public struct BundleDumpSource: BundleDumpSourcing {
    private let launcher: any ProcessLaunching
    private let fileSystem: any CatalogFileSystem
    private let temporaryRoot: URL

    public init(
        launcher: any ProcessLaunching = SystemProcessLauncher(),
        fileSystem: any CatalogFileSystem = DefaultCatalogFileSystem(),
        temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) {
        self.launcher = launcher
        self.fileSystem = fileSystem
        self.temporaryRoot = temporaryRoot
    }

    /// The directory name every export lives under, so a stray one is
    /// identifiable as Cellar's rather than anonymous.
    static let temporaryDirectoryName = "cellar-brewfile"

    public func dump(
        for detection: BrewDetectionState
    ) async throws(BundleDumpError) -> BundleDumpResult {
        let installation: BrewInstallation
        switch detection {
        case .detected(let detected): installation = detected
        case .absent: throw .unavailable(.notInstalled(.standard))
        case .invalid(let url, let error): throw .unavailable(.configuredPathRejected(url, error))
        case .configuredPathMissing(let url): throw .unavailable(.configuredPathMissing(url))
        }

        // Fresh per export. Nothing else is ever written here, and nothing here
        // outlives the attempt.
        let directory = temporaryRoot
            .appendingPathComponent(Self.temporaryDirectoryName)
            .appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("Brewfile")

        // One removal, on every path out — success, failure and cancellation.
        // Two call sites would be two chances to forget.
        defer { try? fileSystem.removeItem(at: directory) }

        do {
            try fileSystem.createDirectory(at: directory)
        } catch {
            throw .launchFailed(.launchFailed(installation.executableURL, code: 0))
        }

        let command = BundleDumpCommand(fileURL: fileURL)
        let process: any LaunchedProcess
        do {
            process = try launcher.launch(ProcessSpec(
                executableURL: installation.executableURL,
                arguments: command.arguments,
                environment: BrewEnvironment.current()
            ))
        } catch {
            throw .launchFailed(Self.processError(error, executableURL: installation.executableURL))
        }

        let outcome: Result<BundleDumpResult, BundleDumpError> = await withTaskCancellationHandler {
            var stdout = Data()
            var stderr = Data()
            for await chunk in process.output {
                switch chunk {
                case .stdout(let bytes): stdout.append(bytes)
                case .stderr(let bytes): stderr.append(bytes)
                }
            }
            let exit = await process.waitForTermination()
            if Task.isCancelled || exit.isCancelled {
                return .failure(.cancelled(rawStdout: stdout, rawStderr: stderr))
            }
            guard exit.isSuccess else {
                return .failure(.commandFailed(
                    status: exit.status,
                    rawStdout: stdout,
                    rawStderr: stderr
                ))
            }
            guard let document = try? fileSystem.contentsMappedIfSafe(of: fileURL) else {
                return .failure(.documentUnreadable)
            }
            // stderr is carried beside the document, never inside it: U6
            // observed an unrelated warning on stderr at exit 0, and a source
            // that concatenated the streams would put it in the user's file.
            return .success(BundleDumpResult(document: document, rawStderr: stderr))
        } onCancel: {
            try? process.send(.interrupt)
        }

        return try outcome.get()
    }

    private static func processError(_ error: any Error, executableURL: URL) -> BrewProcessError {
        if let processError = error as? BrewProcessError { return processError }
        if let posix = error as? POSIXError {
            switch posix.code {
            case .ENOENT, .EACCES, .EPERM, .ENOEXEC:
                return .executableUnavailable(executableURL)
            default:
                return .launchFailed(executableURL, code: posix.code.rawValue)
            }
        }
        return .launchFailed(executableURL, code: Int32(truncatingIfNeeded: (error as NSError).code))
    }
}
