import Foundation
import Testing

@testable import BrewProcess

@Suite("Mutation launch authorization", .timeLimit(.minutes(1)))
struct MutationAuthorizationTests {
    @Test("The default authorizer preserves mutation launch behavior")
    func defaultAuthorizerAllowsLaunch() async throws {
        let launcher = FakeProcessLauncher()
        let process = FakeProcess()
        launcher.enqueue(process)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        let operation = try await runner.start(BrewMutation(arguments: ["tap", "acme/tools"]))
        await launcher.waitForLaunches(atLeast: 1)
        process.terminate(with: BrewExit(status: 0, reason: .exited))

        #expect(await operation.terminal() == .process(
            BrewExit(status: 0, reason: .exited),
            fault: nil
        ))
        #expect(launcher.recordedSpecs.map(\.arguments) == [["tap", "acme/tools"]])
    }

    @Test("Authorization runs at the FIFO front and denial launches nothing")
    func denialAtQueueFrontLaunchesNothing() async throws {
        let launcher = FakeProcessLauncher()
        let firstProcess = FakeProcess()
        launcher.enqueue(firstProcess)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)
        let first = try await runner.start(.mutate(["upgrade", "wget"]))
        await launcher.waitForLaunches(atLeast: 1)

        let authorizer = GateAuthorizer()
        let denied = try await runner.start(
            BrewMutation(arguments: ["untap", "--force", "acme/tools"]),
            authorizer: authorizer
        )
        #expect(await authorizer.hasEntered == false)
        await authorizer.setDecision(.deny(MutationLaunchDenial(code: .evidenceChanged)))

        firstProcess.terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await first.exit()
        await authorizer.waitUntilEntered()
        await authorizer.release()

        #expect(await denied.terminal() == .authorizationDenied(
            MutationLaunchDenial(code: .evidenceChanged)
        ))
        var lines: [LogLine] = []
        for await line in denied.lines { lines.append(line) }
        #expect(lines.isEmpty, "a no-process denial emitted output")
        await launcher.settle()
        #expect(launcher.launchCount == 1, "the denied mutation reached the process seam")

        let deniedSnapshot = await runner.snapshot().operations.first { $0.id == denied.id }
        #expect(deniedSnapshot?.phase == .authorizationDenied(
            MutationLaunchDenial(code: .evidenceChanged)
        ))
        #expect(deniedSnapshot?.phase.exit == nil, "denial fabricated a BrewExit")
    }

    @Test("Cancellation while authorization is suspended wins before spawn")
    func cancellationAfterAuthorizationWinsBeforeSpawn() async throws {
        let launcher = FakeProcessLauncher()
        let authorizer = GateAuthorizer()
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        let operation = try await runner.start(
            BrewMutation(arguments: ["tap", "acme/tools"]),
            authorizer: authorizer
        )
        await authorizer.waitUntilEntered()
        await operation.cancel()
        await authorizer.release()

        guard case .process(let exit, let fault) = await operation.terminal() else {
            Issue.record("expected the existing cancellation terminal")
            return
        }
        #expect(exit.isCancelled)
        #expect(fault == nil)
        #expect(launcher.launchCount == 0)
    }

    @Test("The authorized API cannot represent a read command")
    func authorizedAPIIsMutationOnly() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources/BrewProcess/MutationLaunchAuthorization.swift"),
            encoding: .utf8
        )

        #expect(source.contains("struct BrewMutation"))
        #expect(source.contains("BrewCommand.Kind") == false)
        #expect(source.contains("case read") == false)
    }
}

private actor GateAuthorizer: MutationLaunchAuthorizing {
    private var decision: MutationLaunchDecision = .allow
    private var entered = false
    private var isReleased = false

    var hasEntered: Bool { entered }

    func setDecision(_ decision: MutationLaunchDecision) {
        self.decision = decision
    }

    func release() {
        isReleased = true
    }

    func waitUntilEntered() async {
        while !entered { await Task.yield() }
    }

    func authorizeLaunch() async -> MutationLaunchDecision {
        entered = true
        while !isReleased { await Task.yield() }
        return decision
    }
}
