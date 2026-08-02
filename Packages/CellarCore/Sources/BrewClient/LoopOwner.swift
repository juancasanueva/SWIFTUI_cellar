import Foundation
import Observation

/// Owns the app's long-lived refresh loops, one per id.
///
/// SwiftUI's `.task` ties a loop's lifetime to the scene that started it, which
/// is wrong for work the *application* owns: closing the window that launched
/// Cellar would stop the catalog refresh schedule and drop the sync event
/// subscription (M1 follow-ups #8 and #9). Holding the tasks here — in a value
/// the `App` keeps as `@State`, which outlives every scene — fixes both, and the
/// per-id guard preserves the "a second window must not start a second loop"
/// semantics that `.task` gave for free.
///
/// Deliberately dependency-free: it takes closures, not stores, so it is fully
/// testable in the `swift test` inner loop rather than only through the app
/// target (design D10).
@MainActor
@Observable
public final class LoopOwner {
    /// The running loops. A slot stays claimed for the rest of the launch even
    /// if its body returns: "at most one loop of each kind per launch" is the
    /// guarantee, and re-entering `start` must never re-run one.
    private var loops: [String: Task<Void, Never>] = [:]

    public init() {}

    /// Starts `body` under `id`, or does nothing if that id is already running.
    ///
    /// Idempotent by design: every scene calls this from its own `.task`, and
    /// open → close → open must find the loop already running and return.
    public func start(_ id: String, _ body: @escaping @MainActor () async -> Void) {
        guard loops[id] == nil else { return }
        // Unstructured on purpose. A child task would be cancelled with the
        // caller's scene, which is exactly the behaviour being replaced.
        loops[id] = Task { @MainActor in await body() }
    }

    public func isRunning(_ id: String) -> Bool { loops[id] != nil }

    /// Stops everything. For teardown and tests; the app never calls it, because
    /// the loops are meant to outlive every window.
    public func cancelAll() {
        for loop in loops.values { loop.cancel() }
        loops.removeAll()
    }
}
