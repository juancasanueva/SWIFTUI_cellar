import BrewProcess
import Foundation
import Synchronization

/// Records every `ProcessSpec` anything in scope tries to launch.
///
/// Small on purpose. Its whole job is to make "this wrote a row and spawned
/// **nothing**" an assertion rather than a claim: local metadata is the first
/// user-authored text in the app, so the interesting question is not what the
/// store returns but whether any of it can reach a command vector at all
/// (local-package-metadata LPM2 sc2, LPM3; threat: user free text reaching a
/// command vector).
final class SpyProcessLauncher: ProcessLaunching, Sendable {
    private let recorded = Mutex<[ProcessSpec]>([])

    /// Every spec handed to `launch(_:)`, in order.
    var specs: [ProcessSpec] { recorded.withLock { $0 } }
    var launchCount: Int { recorded.withLock { $0.count } }

    /// Every argument of every launch, flattened — the form the "no fragment of
    /// this text reached argv" assertions read.
    var allArguments: [String] { specs.flatMap(\.arguments) }

    func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess {
        recorded.withLock { $0.append(spec) }
        return SilentProcess()
    }
}

/// A process that produces nothing and exits cleanly.
final class SilentProcess: LaunchedProcess, Sendable {
    let output: AsyncStream<OutputChunk>

    init() {
        let (stream, continuation) = AsyncStream<OutputChunk>.makeStream()
        continuation.finish()
        output = stream
    }

    func send(_ signal: ProcessSignal) throws {}

    func waitForTermination() async -> BrewExit { BrewExit(status: 0, reason: .exited) }
}
