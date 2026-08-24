import BrewProcess

/// Refreshes taps at baseline and once for each tap-domain mutation terminal.
@MainActor
public final class TapRefreshCoordinator {
    private let store: TapStore
    /// The per-package grant report, which rides this domain rather than
    /// declaring one of its own (package-trust PT2 :114-123, DD-3).
    ///
    /// Optional with a default of `nil` in the shipped `mutations:` idiom, so
    /// every existing construction site still compiles and a Cellar without the
    /// per-package surface behaves exactly as it does today.
    private let grants: TrustGrantStore?
    private let mutations: InstalledMutationGate?
    private let refreshRegistry: MutationRefreshRegistry?
    private var installation: BrewInstallation?

    public init(
        store: TapStore,
        grants: TrustGrantStore? = nil,
        mutations: InstalledMutationGate? = nil,
        refreshRegistry: MutationRefreshRegistry? = nil
    ) {
        self.store = store
        self.grants = grants
        self.mutations = mutations
        self.refreshRegistry = refreshRegistry
    }

    public func refresh(using installation: BrewInstallation?) async {
        self.installation = installation
        async let tapRefresh: Void = store.refresh(using: installation)
        async let grantRefresh: Void? = grants?.refresh(using: installation)
        await tapRefresh
        _ = await grantRefresh
    }

    public func refresh(for detection: BrewDetectionState) async {
        installation = detection.installation
        async let tapRefresh: Void = store.refresh(for: detection)
        async let grantRefresh: Void? = grants?.refresh(for: detection)
        await tapRefresh
        _ = await grantRefresh
    }

    public func run() async {
        guard let mutations else { return }
        for await event in mutations.settlements {
            await mutationSettled(event)
        }
    }

    private func mutationSettled(_ event: MutationTerminalEvent?) async {
        store.invalidate()
        grants?.invalidate()
        let result = await performRefresh(for: event)
        if let event, let refreshRegistry {
            await refreshRegistry.complete(event, with: result)
        }
    }

    private func performRefresh(for event: MutationTerminalEvent?) async -> RefreshResult {
        guard let installation else { return .brewUnavailable }
        if let event, event.installationURL != installation.executableURL {
            return .installationChanged
        }
        // The two reads overlap: `BrewCommand.read` is designed to run
        // concurrently and the payloads are independent, so neither blocks the
        // other's adoption (DD-4).
        async let tapRefresh: Void = store.refresh(using: installation)
        async let grantRefresh: Void? = grants?.refresh(using: installation)
        await tapRefresh
        // Decided by the **tap** read alone, and decided before the grant read is
        // consulted at all — a degraded grant read cannot turn a successful tap
        // refresh into a failed one (PT2 :172-178).
        let result = outcome()
        _ = await grantRefresh
        return result
    }

    private func outcome() -> RefreshResult {
        if Task.isCancelled { return .cancelled }
        switch store.state {
        case .loaded: return .refreshed
        case .failed: return .failed
        case .brewAbsent: return .brewUnavailable
        case .idle, .loading: return .failed
        }
    }
}
