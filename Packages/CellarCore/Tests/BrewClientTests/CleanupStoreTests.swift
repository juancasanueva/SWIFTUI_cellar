import BrewProcess
import DiskUsage
import Foundation
import Synchronization
import Testing
@testable import BrewClient
@MainActor
@Suite("Cleanup preview source and store", .timeLimit(.minutes(1)))
struct CleanupStoreTests {
    @Test("Preview source preserves bytes and uses exact read command environment")
    func sourceUsesReadCommandAndPreservesBytes() async throws {
        let stdout = "Would remove: /tmp/archive (12B)\n==> This operation would free approximately 12B of disk space.\n"
        let stderr = "diagnostic\n"
        let launcher = RecordingProcessLauncher([.init(stdout: stdout, stderr: stderr)])
        let source = CleanupPreviewSource(launcher: launcher)
        let request = CleanupPreviewRequest(scope: .full)
        let result = try await source.preview(request, for: .detected(TestInstallation.appleSilicon))
        #expect(result.rawStdout == Data(stdout.utf8))
        #expect(result.rawStderr == Data(stderr.utf8))
        #expect(result.evidence.total == .reportedFooter(bytes: 12))
        let spec = try #require(launcher.specs.first)
        #expect(request.specification.kind == .read)
        #expect(spec.arguments == ["cleanup", "--dry-run", "--prune=all"])
        #expect(spec.environment["HOMEBREW_NO_AUTOREMOVE"] == "1")
        #expect(spec.executableURL == TestInstallation.appleSilicon.executableURL)
    }

    @Test("Absent and invalid brew return typed guidance without spawning")
    func unavailableBrewSpawnsNothing() async {
        let launcher = RecordingProcessLauncher()
        let source = CleanupPreviewSource(launcher: launcher)
        let request = CleanupPreviewRequest(scope: .global)
        let configured = URL(fileURLWithPath: "/missing/brew")
        let absent = await failure { try await source.preview(request, for: .absent) }
        let missing = await failure {
            try await source.preview(request, for: .configuredPathMissing(configured))
        }
        let invalid = await failure {
            try await source.preview(request, for: .invalid(configured, .notExecutable(configured)))
        }
        #expect(absent == CleanupPreviewError.unavailable(.notInstalled(.standard)))
        #expect(missing == CleanupPreviewError.unavailable(.configuredPathMissing(configured)))
        #expect(invalid == CleanupPreviewError.unavailable(
            .configuredPathRejected(configured, .notExecutable(configured))
        ))
        #expect(launcher.launchCount == 0)
    }
    @Test("Cancelling a preview interrupts the process and stays cancelled")
    func sourceCancellation() async {
        let launcher = ControllableProcessLauncher()
        let source = CleanupPreviewSource(launcher: launcher)
        let request = CleanupPreviewRequest(scope: .full)
        let task = Task {
            try await source.preview(request, for: .detected(TestInstallation.appleSilicon))
        }
        await launcher.waitForLaunches(atLeast: 1)
        task.cancel()
        let error = await failure { try await task.value }
        #expect(error?.isCancellation == true)
        #expect(launcher.launchedProcesses.first?.deliveredSignals == [.interrupt])
    }
    @Test("A superseded generation cannot replace the current result")
    func supersededGenerationIsRejected() async {
        let source = ControlledCleanupPreviewSource()
        let store = CleanupStore(source: source)
        store.startPreview(scope: .full, for: .detected(TestInstallation.appleSilicon))
        await source.waitForCalls(1)
        store.startPreview(scope: .full, for: .detected(TestInstallation.appleSilicon))
        await source.waitForCalls(2)
        await source.resolve(call: 1, with: .success(fullPreview(bytes: 22)))
        await settle { store.state(for: .full).result?.evidence.total == .reportedFooter(bytes: 22) }
        await source.resolve(call: 0, with: .success(fullPreview(bytes: 11)))
        await settle()
        #expect(store.state(for: .full).result?.evidence.total == .reportedFooter(bytes: 22))
    }
    @Test("Empty and partial results stay distinct and scoped")
    func emptyAndPartialStatesAreScoped() async {
        let source = ControlledCleanupPreviewSource()
        let store = CleanupStore(source: source)
        store.startPreview(scope: .autoremove, for: .detected(TestInstallation.appleSilicon))
        await source.waitForCalls(1)
        await source.resolve(call: 0, with: .success(""))
        await settle { if case .empty = store.state(for: .autoremove) { true } else { false } }
        store.startPreview(scope: .global, for: .detected(TestInstallation.appleSilicon))
        await source.waitForCalls(2)
        await source.resolve(call: 1, with: .success("future Homebrew prose\n"))
        await settle { if case .partial = store.state(for: .global) { true } else { false } }
        let stayedEmpty = if case .empty = store.state(for: .autoremove) { true } else { false }
        #expect(stayedEmpty)
    }
    @Test("Start, failure, cancellation, and explicit invalidation retain last-good evidence as stale")
    func lastGoodEvidenceStaysStale() async {
        let source = ControlledCleanupPreviewSource()
        let store = CleanupStore(source: source)
        store.startPreview(scope: .full, for: .detected(TestInstallation.appleSilicon))
        await source.waitForCalls(1)
        await source.resolve(call: 0, with: .success(fullPreview(bytes: 22)))
        await settle { store.state(for: .full).result != nil }
        let lastGood = store.state(for: .full).result
        store.startPreview(scope: .full, for: .detected(TestInstallation.appleSilicon))
        await source.waitForCalls(2)
        #expect(store.state(for: .full) == .loading(stale: lastGood))
        await source.resolve(call: 1, with: .failure(.commandFailed(
            status: 1,
            rawStdout: Data(),
            rawStderr: Data("locked\n".utf8)
        )))
        await settle { store.state(for: .full).failure != nil }
        #expect(store.state(for: .full).failure == .commandFailed(
            status: 1, rawStdout: Data(), rawStderr: Data("locked\n".utf8)
        ))
        #expect(store.state(for: .full).staleResult == lastGood)
        store.startPreview(scope: .full, for: .detected(TestInstallation.appleSilicon))
        await source.waitForCalls(3)
        store.cancelPreview(for: .full)
        #expect(store.state(for: .full) == .cancelled(stale: lastGood))
        await source.resolve(call: 2, with: .success(fullPreview(bytes: 99)))
        await settle()
        #expect(store.state(for: .full) == .cancelled(stale: lastGood))
        store.markStale(.full)
        #expect(store.state(for: .full) == .stale(lastGood!))
    }
    private func failure<T: Sendable>(
        _ operation: () async throws -> T
    ) async -> CleanupPreviewError? {
        do {
            _ = try await operation()
            Issue.record("Expected cleanup preview failure")
            return nil
        } catch let error as CleanupPreviewError {
            return error
        } catch {
            Issue.record("Unexpected error type: \(error)")
            return nil
        }
    }
    private func settle(_ condition: @MainActor () -> Bool = { true }) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
        #expect(condition())
    }
    private func fullPreview(bytes: Int64) -> String {
        "Would remove: /tmp/archive (\(bytes)B)\n"
            + "==> This operation would free approximately \(bytes)B of disk space.\n"
    }
}
private actor ControlledCleanupPreviewSource: CleanupPreviewSourcing {
    enum Response: Sendable { case success(String), failure(CleanupPreviewError) }
    private struct Pending {
        let request: CleanupPreviewRequest; let diskUsage: CleanupDiskUsageContext?
        let continuation: CheckedContinuation<Response, Never>
    }
    private var pending: [Pending] = []
    func preview(
        _ request: CleanupPreviewRequest,
        for detection: BrewDetectionState,
        diskUsage: CleanupDiskUsageContext?
    ) async throws(CleanupPreviewError) -> CleanupPreviewResult {
        let response = await withCheckedContinuation { continuation in
            pending.append(.init(request: request, diskUsage: diskUsage, continuation: continuation))
        }
        switch response {
        case .success(let stdout):
            return CleanupParser.parse(
                request, rawStdout: Data(stdout.utf8), rawStderr: Data(), diskUsage: diskUsage
            )
        case .failure(let error): throw error
        }
    }
    func waitForCalls(_ count: Int) async { while pending.count < count { await Task.yield() } }
    func resolve(call index: Int, with response: Response) { pending[index].continuation.resume(returning: response) }
}
