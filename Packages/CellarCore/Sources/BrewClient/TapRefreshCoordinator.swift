import BrewProcess

/// Refreshes taps at baseline and once for each tap-domain mutation terminal.
@MainActor
public final class TapRefreshCoordinator {
    private let store: TapStore
    private let mutations: InstalledMutationGate?
    private let refreshRegistry: MutationRefreshRegistry?
    private var installation: BrewInstallation?

    public init(
        store: TapStore,
        mutations: InstalledMutationGate? = nil,
        refreshRegistry: MutationRefreshRegistry? = nil
    ) {
        self.store = store
        self.mutations = mutations
        self.refreshRegistry = refreshRegistry
    }

    public func refresh(using installation: BrewInstallation?) async {
        self.installation = installation
        await store.refresh(using: installation)
    }

    public func refresh(for detection: BrewDetectionState) async {
        installation = detection.installation
        await store.refresh(for: detection)
    }

    public func run() async {
        guard let mutations else { return }
        for await event in mutations.settlements {
            await mutationSettled(event)
        }
    }

    private func mutationSettled(_ event: MutationTerminalEvent?) async {
        store.invalidate()
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
        await store.refresh(using: installation)
        if Task.isCancelled { return .cancelled }
        switch store.state {
        case .loaded: return .refreshed
        case .failed: return .failed
        case .brewAbsent: return .brewUnavailable
        case .idle, .loading: return .failed
        }
    }
}
