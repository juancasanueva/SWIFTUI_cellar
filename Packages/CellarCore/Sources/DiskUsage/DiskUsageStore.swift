import Catalog
import Foundation
import Observation

@MainActor
@Observable
public final class DiskUsageStore {
    private struct ScanConfiguration {
        let roots: HomebrewRoots
        let formulaLinks: [PackageID: FormulaLinkState]
        let scanner: any DiskUsageScanning
    }

    public private(set) var visibleSnapshot: DiskUsageSnapshot?
    public private(set) var incrementalPackages: [PackageID: DiskPackageUsage] = [:]
    public private(set) var progress: DiskUsageProgress?
    public private(set) var warnings: [DiskUsageWarning] = []
    public private(set) var isStale = false
    public private(set) var isScanning = false
    public private(set) var invalidatedAreas: Set<DiskArea> = []

    @ObservationIgnored private let cache: any DiskUsageCaching
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanConfiguration: ScanConfiguration?

    public init(
        cache: any DiskUsageCaching,
        initialSnapshot: DiskUsageSnapshot? = nil,
        initiallyStale: Bool = false
    ) {
        self.cache = cache
        visibleSnapshot = initialSnapshot
        warnings = initialSnapshot?.warnings ?? []
        isStale = initiallyStale && initialSnapshot != nil
    }

    /// Whether a view arriving on screen has any scanning left to ask for.
    ///
    /// `false` while a scan is in flight — restarting it on entry would throw
    /// away its progress — and while the held snapshot is still fresh, since
    /// mutations already invalidate the areas they touch and the store rescans
    /// itself on invalidation.
    public var needsEntryScan: Bool {
        if isScanning { return false }
        return visibleSnapshot == nil || isStale
    }

    public var visiblePackages: [DiskPackageUsage] {
        guard !incrementalPackages.isEmpty else { return visibleSnapshot?.packages ?? [] }
        var overlaid = Dictionary(
            uniqueKeysWithValues: (visibleSnapshot?.packages ?? []).map { ($0.id, $0) }
        )
        overlaid.merge(incrementalPackages) { _, fresh in fresh }
        return DiskUsageSnapshot.sorted(Array(overlaid.values))
    }

    public func loadCached(for roots: DiskRootsIdentity) async {
        guard let cached = try? await cache.load(), cached.isComplete, cached.roots == roots else {
            visibleSnapshot = nil
            isStale = false
            return
        }
        visibleSnapshot = cached
        warnings = []
        isStale = true
    }

    @discardableResult
    public func beginScan() -> UUID {
        scanTask?.cancel()
        scanTask = nil
        let next = UUID()
        generation = next
        incrementalPackages = [:]
        progress = .init(completedUnits: 0, discoveredUnits: 0)
        warnings = []
        isScanning = true
        return next
    }

    public func startScan(
        roots: HomebrewRoots,
        formulaLinks: [PackageID: FormulaLinkState] = [:],
        scanner: any DiskUsageScanning = DiskUsageEngine()
    ) {
        let configuration = ScanConfiguration(
            roots: roots,
            formulaLinks: formulaLinks,
            scanner: scanner
        )
        scanConfiguration = configuration
        startScan(configuration)
    }

    private func startScan(_ configuration: ScanConfiguration) {
        let candidate = beginScan()
        scanTask = Task { [weak self] in
            guard let self else { return }
            let events = await configuration.scanner.scan(
                roots: configuration.roots,
                formulaLinks: configuration.formulaLinks
            )
            do {
                for try await event in events {
                    try Task.checkCancellation()
                    await self.accept(event, generation: candidate)
                }
            } catch {
                self.finishCancelledScan(generation: candidate)
            }
        }
    }

    public func cancel() {
        scanTask?.cancel()
        scanTask = nil
        finishCancelledScan(generation: generation)
    }

    private func finishCancelledScan(generation candidate: UUID?) {
        guard generation == candidate else { return }
        generation = nil
        isScanning = false
        progress = nil
        incrementalPackages = [:]
    }

    public func invalidate(_ areas: Set<DiskArea>) {
        guard !areas.isEmpty else { return }
        invalidatedAreas.formUnion(areas)
        isStale = visibleSnapshot != nil
        if let scanConfiguration { startScan(scanConfiguration) }
    }

    public func accept(_ event: DiskUsageEvent, generation candidate: UUID) async {
        guard generation == candidate else { return }
        switch event {
        case .started:
            break
        case .progress(let next):
            progress = .init(
                completedUnits: max(progress?.completedUnits ?? 0, next.completedUnits),
                discoveredUnits: max(progress?.discoveredUnits ?? 0, next.discoveredUnits)
            )
        case .version(let version):
            let packageID = version.id.package
            var versions = incrementalPackages[packageID]?.versions ?? []
            if let index = versions.firstIndex(where: { $0.id == version.id }) {
                versions[index] = version
            } else {
                versions.append(version)
            }
            incrementalPackages[packageID] = DiskPackageUsage(id: packageID, versions: versions)
        case .package(let package):
            incrementalPackages[package.id] = package
        case .warning(let warning):
            if !warnings.contains(warning) { warnings.append(warning) }
        case .rootCompleted:
            break
        case .completed(let snapshot):
            if snapshot.isComplete {
                visibleSnapshot = snapshot
                incrementalPackages = [:]
                warnings = []
                isStale = false
                invalidatedAreas = []
                try? await cache.save(snapshot)
            } else {
                incrementalPackages = Dictionary(uniqueKeysWithValues: snapshot.packages.map { ($0.id, $0) })
                warnings = snapshot.warnings
            }
            isScanning = false
            progress = nil
            generation = nil
            scanTask = nil
        }
    }
}
