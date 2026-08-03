import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// One `OperationCenter` with the pieces around it, shared by the two suites
/// that cover it.
///
/// Extracted rather than duplicated because the centre's surface is wide enough
/// to need two suites — submission and streaming in one, the gate, cancel,
/// confirmation and projections in the other — and both drive it identically.
@MainActor
struct CenterHarness {
    let launcher: ControllableProcessLauncher
    let gate: InstalledMutationGate
    let center: OperationCenter
    /// The drafts the centre submitted, when the harness's own recorder is the
    /// one wired in. A test that injects `history:` reads that one instead.
    let recorder: RecordingHistoryRecorder

    static let wget = PackageID(kind: .formula, name: "wget")
    static let git = PackageID(kind: .formula, name: "git")
    static let iterm = PackageID(kind: .cask, name: "iterm2")

    init(
        attached: Bool = true,
        honoursInterrupt: Bool = true,
        history: (any HistoryRecording)? = nil
    ) {
        launcher = ControllableProcessLauncher(honoursInterrupt: honoursInterrupt)
        gate = InstalledMutationGate()
        recorder = RecordingHistoryRecorder()
        center = OperationCenter(
            gate: gate,
            history: history ?? recorder,
            launcherFactory: { [launcher] _ in launcher }
        )
        if attached {
            center.attach(installation: TestInstallation.appleSilicon)
        }
    }

    /// Lets pending main-actor work run without depending on wall-clock time.
    func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    /// Main-actor polling, for the places a fixed number of yields is not
    /// enough — draining two thousand lines crosses a stream and an actor hop.
    ///
    /// `TestPoll` cannot serve here: its condition is `@Sendable`, so it would
    /// have to be evaluated off the main actor.
    func poll(until condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    /// Terminates the `index`-th spawned process and lets the centre observe it.
    ///
    /// `TestPoll.until` returns **silently** on timeout, so the shipped version
    /// of this method indexed `launchedProcesses[index]` on a process that might
    /// never have been launched. A timing regression therefore trapped and took
    /// the whole suite down with it, naming nothing. `#require` turns that into
    /// one named failed expectation, attributed to the calling test through
    /// `sourceLocation` (design D11).
    func finish(
        call index: Int,
        status: Int32 = 0,
        timeout: Duration = .seconds(5),
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        await TestPoll.until(timeout: timeout, self.launcher.launchCount >= index + 1)
        let process = try #require(
            launcher.launchedProcesses.indices.contains(index)
                ? launcher.launchedProcesses[index]
                : nil,
            "no process was launched for call \(index) within \(timeout)",
            sourceLocation: sourceLocation
        )
        process.terminate(with: BrewExit(status: status, reason: .exited))
        await settle()
    }
}
