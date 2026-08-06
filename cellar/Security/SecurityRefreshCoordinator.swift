//
//  SecurityRefreshCoordinator.swift
//  cellar
//

import BrewClient
import Foundation
import SecurityKit

/// Owns the cadence: a daily schedule, and a re-scan after an install or upgrade.
///
/// ## Why it is here rather than beside its sibling
///
/// The shipped `DiskUsageRefreshCoordinator` lives in
/// `Packages/CellarCore/Sources/BrewClient/`. This one cannot follow it there —
/// no CellarCore target may import both `BrewClient` and `SecurityKit` — so it is
/// the *pattern* that is reused and the location that deliberately differs. That
/// is a named cost of the placement decision, not an oversight.
///
/// ## Consent is read per trigger
///
/// Never captured at construction. A grant read once would keep firing for the
/// rest of the launch after the user turned scanning off, and "off means fully
/// off" would hold only until the next relaunch. Reading it at each trigger is
/// what makes revocation take effect on the very next one.
///
/// The engine checks consent again on every egress path regardless. This is not
/// redundancy for its own sake: the engine's check stops the *request*, and this
/// one stops the scheduled work from starting at all, so a revoked user's machine
/// is not waking up every fifteen minutes to be refused.
nonisolated struct SecurityRefreshCoordinator: Sendable {
    private let scan: @Sendable () async -> Void
    private let isConsented: @Sendable () async -> Bool

    init(
        scan: @escaping @Sendable () async -> Void,
        isConsented: @escaping @Sendable () async -> Bool
    ) {
        self.scan = scan
        self.isConsented = isConsented
    }

    /// The scheduled ingress. Staleness itself is `SecurityRefreshPolicy`'s
    /// decision, made inside the engine against the cache's wall-clock
    /// `fetchedAt` — this only decides whether to ask at all.
    func refreshIfNeeded() async {
        guard await isConsented() else { return }
        await scan()
    }

    /// The post-mutation ingress: an install or upgrade changed what is installed,
    /// so what was asked about is no longer what is here.
    func mutationCompleted() async {
        guard await isConsented() else { return }
        await scan()
    }

    /// Watches a mutation gate and re-scans when its terminals arrive.
    ///
    /// `DiskUsageRefreshCoordinator.run`'s shape. Long-lived, cancelled with the
    /// scene, and it re-reads consent through `mutationCompleted` on every
    /// terminal rather than deciding once on the way in.
    ///
    /// `@MainActor` only because `InstalledMutationGate` is: the coordinator
    /// itself is `nonisolated`, and the two ingress methods above are callable
    /// from anywhere, which is what keeps them testable without a main-actor hop.
    @MainActor
    func run(observing gate: InstalledMutationGate) async {
        for await _ in gate.terminals {
            await mutationCompleted()
        }
    }
}
