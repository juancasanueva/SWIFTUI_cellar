import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog
@testable import DiskUsage

@MainActor
@Suite("Cleanup authorization", .timeLimit(.minutes(1)))
struct CleanupAuthorizationTests {
    @Test("Confirmation discloses typed evidence and Full cleanup truthfully")
    func confirmationDisclosureIsTypedAndComplete() throws {
        let center = OperationCenter()
        let preview = Self.preview(
            scope: .full,
            stdout: "Would remove: /cache/download (12B)\n"
                + "==> This operation would free approximately 12B of disk space.\n"
        )

        let request = try #require(center.requestCleanup(preview: .content(preview)))
        let disclosure = try #require(request.cleanupDisclosure)

        #expect(disclosure.scope == .full)
        #expect(disclosure.previewRequest == CleanupPreviewRequest(id: preview.requestID, scope: .full))
        #expect(request.command.arguments == ["cleanup", "--prune=all"])
        #expect(request.displayCommand == "brew cleanup --prune=all")
        #expect(disclosure.effects == [.removesCleanupCandidates, .removesCachedDownloadsRegardlessOfAge])
        #expect(disclosure.orphanNames == [])
        #expect(disclosure.orphanCount == nil)
        #expect(disclosure.total == .reportedFooter(bytes: 12))
        #expect(disclosure.provenance == preview.provenance)
        #expect(disclosure.fullWarning == CleanupConfirmationDisclosure.fullCleanupWarning)
        #expect(request.warningText == CleanupConfirmationDisclosure.fullCleanupWarning)

        let autoremove = Self.preview(
            scope: .autoremove,
            stdout: "==> Would autoremove 2 unneeded formulae:\nwget\ngit\n"
        )
        let autoremoveRequest = try #require(center.requestCleanup(preview: .content(autoremove)))
        let autoremoveDisclosure = try #require(autoremoveRequest.cleanupDisclosure)
        #expect(autoremoveDisclosure.effects == [.removesUnusedFormulae])
        #expect(autoremoveDisclosure.orphanNames == ["wget", "git"])
        #expect(autoremoveDisclosure.orphanCount == 2)
        #expect(autoremoveDisclosure.total == .unknown)
        #expect(autoremoveDisclosure.fullWarning == nil)
    }

    @Test("Only fresh nonempty complete preview state can become a confirmation")
    func staleEmptyAndPartialStatesCannotConfirm() {
        let center = OperationCenter()
        let content = Self.preview(scope: .global, stdout: "Would remove: /cache/a (1B)\n")
        let empty = Self.preview(scope: .global, stdout: "")
        let partial = Self.preview(scope: .global, stdout: "unrecognized prose\n")

        #expect(center.requestCleanup(preview: .stale(content)) == nil)
        #expect(center.requestCleanup(preview: .empty(empty)) == nil)
        #expect(center.requestCleanup(preview: .partial(partial)) == nil)
        #expect(center.pendingConfirmation == nil)
        #expect(center.items.isEmpty)
    }

    @Test("Queue-front authorization reruns the identical request and preserves FIFO and local policy")
    func matchingEvidenceLaunchesOnceAtFIFOFront() async throws {
        let launcher = ControllableProcessLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: TestInstallation.appleSilicon)
        let blocker = center.submit(try #require(MutationCommand.install(formula: "wget")))
        await launcher.waitForLaunches(atLeast: 1)

        let preview = Self.preview(scope: .full, stdout: "Would remove: /cache/a (1B)\n")
        let source = ScriptedCleanupPreviewSource([.success(preview)])
        let request = try #require(center.requestCleanup(preview: .content(preview)))
        var updates: [CleanupAuthorizationUpdate] = []
        let submitted = center.confirmCleanup(
            request,
            source: source,
            detection: .detected(TestInstallation.appleSilicon),
            publish: { updates.append($0) }
        )
        let item = try #require(submitted)

        #expect(await source.requests.isEmpty)
        #expect(launcher.launchCount == 1)
        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        await Self.poll {
            let requestCount = await source.requests.count
            return blocker.isTerminal && requestCount == 1
        }
        await launcher.waitForLaunches(atLeast: 2)

        #expect(await source.requests == [CleanupPreviewRequest(id: preview.requestID, scope: .full)])
        #expect(launcher.recordedSpecs[1].arguments == ["cleanup", "--prune=all"])
        #expect(launcher.recordedSpecs[1].environment["HOMEBREW_NO_AUTOREMOVE"] == "1")
        #expect(updates == [.refreshed(preview)])
        launcher.launchedProcesses[1].terminate(with: BrewExit(status: 0, reason: .exited))
        await Self.poll { item.isTerminal }
        #expect(item.outcome == .succeeded)
        #expect(launcher.launchCount == 2)
    }

    @Test("Changed, empty, failed, cancelled, and unavailable evidence fail closed")
    func nonmatchingEvidenceSpawnsNothing() async throws {
        for testCase in DenialCase.all {
            let launcher = ControllableProcessLauncher()
            let center = OperationCenter(launcherFactory: { _ in launcher })
            center.attach(installation: TestInstallation.appleSilicon)
            let reviewed = Self.preview(scope: .global, stdout: "Would remove: /cache/a (1B)\n")
            let outcome = testCase.outcome(reviewed: reviewed)
            let source = ScriptedCleanupPreviewSource([outcome])
            let request = try #require(center.requestCleanup(preview: .content(reviewed)))
            var updates: [CleanupAuthorizationUpdate] = []

            let submitted = center.confirmCleanup(
                request,
                source: source,
                detection: .detected(TestInstallation.appleSilicon),
                publish: { updates.append($0) }
            )
            let item = try #require(submitted)
            await Self.poll { item.isTerminal }

            #expect(launcher.launchCount == 0, "\(testCase.kind) reached the process seam")
            #expect(item.outcome == .authorizationDenied(testCase.denial))
            #expect(updates == [testCase.update(outcome: outcome, reviewed: reviewed)])
            #expect(center.pendingConfirmation == nil, "denial silently reconfirmed without user review")
        }
    }

    nonisolated private static func preview(
        scope: CleanupScope,
        stdout: String
    ) -> CleanupPreviewResult {
        let request = CleanupPreviewRequest(id: UUID(), scope: scope)
        return CleanupParser.parse(request, rawStdout: Data(stdout.utf8), rawStderr: Data())
    }

    private static func poll(until condition: @escaping @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
    }
}

extension CleanupAuthorizationTests {
    struct DenialCase: Sendable {
        enum Kind: Sendable { case changed, empty, failed, cancelled, unavailable }
        let kind: Kind
        var denial: MutationLaunchDenial.Code {
            switch kind {
            case .changed, .empty: .evidenceChanged
            case .failed, .cancelled, .unavailable: .evidenceUnavailable
            }
        }
        func outcome(
            reviewed: CleanupPreviewResult
        ) -> Result<CleanupPreviewResult, CleanupPreviewError> {
            switch kind {
            case .changed:
                .success(CleanupAuthorizationTests.preview(
                    scope: .global,
                    stdout: "Would remove: /cache/b (2B)\n"
                ))
            case .empty: .success(CleanupAuthorizationTests.preview(scope: .global, stdout: ""))
            case .failed: .failure(.commandFailed(status: 1, rawStdout: Data(), rawStderr: Data("failed".utf8)))
            case .cancelled: .failure(.cancelled(rawStdout: Data(), rawStderr: Data()))
            case .unavailable: .failure(.unavailable(.notInstalled(.standard)))
            }
        }
        func update(
            outcome: Result<CleanupPreviewResult, CleanupPreviewError>,
            reviewed: CleanupPreviewResult
        ) -> CleanupAuthorizationUpdate {
            switch outcome {
            case .success(let refreshed): .refreshed(refreshed)
            case .failure(let error): .stale(reviewed: reviewed, error: error)
            }
        }
        static let all = [
            DenialCase(kind: .changed), .init(kind: .empty), .init(kind: .failed),
            .init(kind: .cancelled), .init(kind: .unavailable),
        ]
    }
}

actor ScriptedCleanupPreviewSource: CleanupPreviewSourcing {
    private var outcomes: [Result<CleanupPreviewResult, CleanupPreviewError>]
    private(set) var requests: [CleanupPreviewRequest] = []

    init(_ outcomes: [Result<CleanupPreviewResult, CleanupPreviewError>]) { self.outcomes = outcomes }

    func preview(
        _ request: CleanupPreviewRequest,
        for _: BrewDetectionState,
        diskUsage _: CleanupDiskUsageContext?
    ) async throws(CleanupPreviewError) -> CleanupPreviewResult {
        requests.append(request)
        guard !outcomes.isEmpty else {
            throw .commandFailed(status: 99, rawStdout: Data(), rawStderr: Data())
        }
        switch outcomes.removeFirst() {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}
