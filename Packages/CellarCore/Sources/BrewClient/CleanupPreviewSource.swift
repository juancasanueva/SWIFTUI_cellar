import BrewProcess
import Foundation
public enum CleanupPreviewError: Error, Sendable, Equatable {
    case unavailable(InstalledAbsence)
    case commandFailed(status: Int32, rawStdout: Data, rawStderr: Data)
    case launchFailed(BrewProcessError)
    case cancelled(rawStdout: Data, rawStderr: Data)
    public var isCancellation: Bool { if case .cancelled = self { true } else { false } }
}
public protocol CleanupPreviewSourcing: Sendable {
    func preview(
        _ request: CleanupPreviewRequest,
        for detection: BrewDetectionState,
        diskUsage: CleanupDiskUsageContext?
    ) async throws(CleanupPreviewError) -> CleanupPreviewResult
}
extension CleanupPreviewSourcing {
    func previewResult(
        _ request: CleanupPreviewRequest,
        for detection: BrewDetectionState,
        diskUsage: CleanupDiskUsageContext?
    ) async -> Result<CleanupPreviewResult, CleanupPreviewError> {
        do {
            return .success(try await preview(request, for: detection, diskUsage: diskUsage))
        } catch {
            return .failure(error)
        }
    }
}
public struct CleanupPreviewSource: CleanupPreviewSourcing {
    private let launcher: any ProcessLaunching
    public init(launcher: any ProcessLaunching = SystemProcessLauncher()) { self.launcher = launcher }
    public func preview(
        _ request: CleanupPreviewRequest,
        for detection: BrewDetectionState
    ) async throws(CleanupPreviewError) -> CleanupPreviewResult {
        try await preview(request, for: detection, diskUsage: nil)
    }
    public func preview(
        _ request: CleanupPreviewRequest,
        for detection: BrewDetectionState,
        diskUsage: CleanupDiskUsageContext?
    ) async throws(CleanupPreviewError) -> CleanupPreviewResult {
        let installation: BrewInstallation
        switch detection {
        case .detected(let detected): installation = detected
        case .absent: throw .unavailable(.notInstalled(.standard))
        case .invalid(let url, let error): throw .unavailable(.configuredPathRejected(url, error))
        case .configuredPathMissing(let url): throw .unavailable(.configuredPathMissing(url))
        }
        let process: any LaunchedProcess
        do {
            process = try launcher.launch(ProcessSpec(
                executableURL: installation.executableURL,
                arguments: request.specification.arguments,
                environment: BrewEnvironment.current(
                    commandOverrides: request.specification.environmentOverrides
                )
            ))
        } catch {
            throw .launchFailed(Self.processError(error, executableURL: installation.executableURL))
        }
        let outcome: Result<CleanupPreviewResult, CleanupPreviewError> = await withTaskCancellationHandler {
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
            return .success(CleanupParser.parse(
                request,
                rawStdout: stdout,
                rawStderr: stderr,
                diskUsage: diskUsage
            ))
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
