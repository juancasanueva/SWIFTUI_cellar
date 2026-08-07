import BrewProcess
import Foundation

/// The seam that produces one doctor outcome.
///
/// **No `throws`, by design (HD1).** `brew doctor` reports warnings by exiting
/// `1` and writing its whole report to stderr, so "non-zero" is the informative
/// answer rather than a failure. Encoding that as a thrown error would make the
/// health score read a failure where there is none.
///
/// A `throws(DoctorError)` variant with `.issues` returned normally was rejected
/// for a sharper reason than taste: it would keep non-zero-as-error
/// *expressible*, so a later "simplification" back onto the three JSON payload
/// sources' template would still compile. With no `throws` in the signature at
/// all, that simplification is a compile error rather than a review finding.
///
/// This is licensed verbatim by `brew-execution`, not a contradiction of it: "a
/// non-zero status MUST NOT be raised as a thrown error, because `brew` uses
/// exit codes semantically". The "non-zero is a failure" rule lives one layer
/// above, in the three payload sources, each of which adopted it for its own
/// document reasons — and `DoctorPayloadQuarantineTests` proves it is still
/// theirs (decision D7).
public protocol DoctorSourcing: Sendable {
    func run(using installation: BrewInstallation) async -> DoctorOutcome
}

/// The production source: one `brew doctor` run.
///
/// Glue only, in the `CleanupPreviewSource` shape — start, drain both pipes
/// separately, wait, classify, hand the bytes to the parser. Keeping it this
/// thin is what lets every interesting decision be tested without a process.
///
/// The two pipes are accumulated into two separate `Data` values and stay
/// separate all the way into the evidence. Nothing here concatenates,
/// interleaves, trims or folds one into the other.
public struct BrewDoctorSource: DoctorSourcing {
    private let launcher: any ProcessLaunching

    public init(launcher: any ProcessLaunching = SystemProcessLauncher()) {
        self.launcher = launcher
    }

    public func run(using installation: BrewInstallation) async -> DoctorOutcome {
        let process: any LaunchedProcess
        do {
            process = try launcher.launch(ProcessSpec(
                executableURL: installation.executableURL,
                arguments: DoctorCommand.command.arguments,
                environment: BrewEnvironment.current(
                    commandOverrides: DoctorCommand.command.environmentOverrides
                )
            ))
        } catch {
            return .unavailable(Self.spawnFailure(error, executableURL: installation.executableURL))
        }

        return await withTaskCancellationHandler {
            var stdout = Data()
            var stderr = Data()
            for await chunk in process.output {
                switch chunk {
                case .stdout(let bytes): stdout.append(bytes)
                case .stderr(let bytes): stderr.append(bytes)
                }
            }
            let exit = await process.waitForTermination()

            // Classification, in this order (HD1). Only the first two arms can
            // reach `.unavailable`, and neither of them describes a run that
            // completed — which is what makes "a completed non-zero run is
            // always an ordinary outcome" true by construction.
            if Task.isCancelled || exit.isCancelled { return .unavailable(.cancelled) }
            if case .signalled(let signal) = exit.reason { return .unavailable(.signalled(signal)) }

            let evidence = await DoctorParser.parse(rawStdout: stdout, rawStderr: stderr)
            return exit.isSuccess ? .clean(evidence) : .issues(evidence)
        } onCancel: {
            try? process.send(.interrupt)
        }
    }

    private static func spawnFailure(
        _ error: any Error,
        executableURL: URL
    ) -> DoctorUnavailableReason {
        guard let processError = error as? BrewProcessError else {
            return .launchFailed(.launchFailed(
                executableURL,
                code: Int32(truncatingIfNeeded: (error as NSError).code)
            ))
        }
        switch processError {
        case .executableUnavailable:
            // Detection said there was a brew here and the spawn disagrees.
            // Guidance, not a failure the user can act on differently.
            return .brewUnavailable
        case .launchFailed:
            return .launchFailed(processError)
        case .cancelledUnresponsive:
            return .cancelled
        }
    }
}
