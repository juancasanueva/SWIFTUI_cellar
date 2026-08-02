import CellarTestSupport
import Foundation

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

    static let wget = PackageID(kind: .formula, name: "wget")
    static let git = PackageID(kind: .formula, name: "git")
    static let iterm = PackageID(kind: .cask, name: "iterm2")

    init(attached: Bool = true) {
        launcher = ControllableProcessLauncher()
        gate = InstalledMutationGate()
        center = OperationCenter(gate: gate, launcherFactory: { [launcher] _ in launcher })
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
    func finish(call index: Int, status: Int32 = 0) async {
        await launcher.waitForLaunches(atLeast: index + 1)
        launcher.launchedProcesses[index]
            .terminate(with: BrewExit(status: status, reason: .exited))
        await settle()
    }
}
