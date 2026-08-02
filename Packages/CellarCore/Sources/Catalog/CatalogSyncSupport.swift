import Foundation

/// Small vocabulary the sync engine leans on, kept out of the engine file so
/// neither outgrows the project's limits.

extension CatalogResource {
    /// The two resources that carry packages. Analytics is a separate, optional
    /// join.
    public static let payloadResources: [CatalogResource] = [.formulae, .casks]

    /// The two optional install-count endpoints.
    public static let analyticsResources: [CatalogResource] = [.analyticsFormula, .analyticsCask]

    var kind: PackageKind {
        switch self {
        case .formulae, .analyticsFormula: .formula
        case .casks, .analyticsCask: .cask
        }
    }
}

extension CatalogSyncError {
    /// Normalises anything thrown inside a sync into the closed taxonomy.
    static func from(_ error: any Error) -> CatalogSyncError {
        switch error {
        case let known as CatalogSyncError: known
        case is CancellationError: .cancelled
        default: .malformedPayload
        }
    }
}

extension CatalogDecoder {
    /// Decodes a staged payload off the caller's executor.
    ///
    /// `@concurrent` rather than a plain `nonisolated func`: a synchronous
    /// nonisolated call from an actor still runs *on* that actor, which is the
    /// head-of-line block this whole design avoids (design D2).
    @concurrent
    public static func decode(
        _ resource: CatalogResource,
        at url: URL
    ) async throws -> DecodedResource {
        switch resource {
        case .formulae:
            try decodeFormulae(contentsOf: url, deletingAfterwards: true)
        case .casks:
            try decodeCasks(contentsOf: url, deletingAfterwards: true)
        case .analyticsFormula, .analyticsCask:
            throw CatalogSyncError.malformedPayload
        }
    }

    /// Decodes a staged analytics payload off the caller's executor.
    @concurrent
    public static func decodeAnalytics(at url: URL, kind: PackageKind) async throws -> AnalyticsIndex {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw CatalogSyncError.malformedPayload
        }
        return try AnalyticsIndex.decode(data, kind: kind)
    }
}

extension AnalyticsIndex {
    /// The counts a previous snapshot already carries for one namespace.
    ///
    /// A slightly stale install number beats blanking the column when an
    /// analytics endpoint fails (catalog-sync CS9).
    init(carriedOverFor kind: PackageKind, in snapshot: CatalogSnapshot?) {
        guard let snapshot else {
            self.init()
            return
        }
        var counts: [PackageID: Int] = [:]
        for package in snapshot.packages where package.kind == kind {
            if let count = package.installCount365d { counts[package.id] = count }
        }
        self.init(counts: counts)
    }
}
