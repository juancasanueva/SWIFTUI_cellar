import DiskUsage

@MainActor
public final class DiskUsageRefreshCoordinator {
    private let store: DiskUsageStore
    private let mutations: InstalledMutationGate?
    private let refreshRegistry: MutationRefreshRegistry?

    public init(
        store: DiskUsageStore,
        mutations: InstalledMutationGate? = nil,
        refreshRegistry: MutationRefreshRegistry? = nil
    ) {
        self.store = store
        self.mutations = mutations
        self.refreshRegistry = refreshRegistry
    }

    public func invalidate(_ areas: Set<DiskArea>) {
        store.invalidate(areas)
    }

    public func run() async {
        guard let mutations else { return }
        for await event in mutations.settlements {
            guard let event else { continue }
            store.invalidate(event.diskAreas)
            if let refreshRegistry {
                await refreshRegistry.complete(event, with: .refreshed)
            }
        }
    }
}
