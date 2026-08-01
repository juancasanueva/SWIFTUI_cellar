import Foundation

/// One decoded resource: the projected records plus what was lost getting there.
public struct DecodedResource: Sendable {
    public let packages: [CatalogPackage]
    public let skippedRecordCount: Int

    public init(packages: [CatalogPackage], skippedRecordCount: Int) {
        self.packages = packages
        self.skippedRecordCount = skippedRecordCount
    }

    public static let empty = DecodedResource(packages: [], skippedRecordCount: 0)
}

/// Turns published payloads into the slim persisted projection.
///
/// Every entry point is a pure function over `Data`, which is what makes the
/// whole decode path testable without a network, a file system, or a clock.
public enum CatalogDecoder {
    /// The only taps this catalog covers (package-detail PD6).
    ///
    /// A record from any other tap is out of scope, not malformed: it is dropped
    /// silently and never counted as a skipped record.
    static let coveredTaps: [PackageKind: String] = [
        .formula: "homebrew/core",
        .cask: "homebrew/cask"
    ]

    // MARK: - Staged payloads

    /// Projects a payload straight off disk.
    ///
    /// Three things keep the 40 MB dump from becoming a 400 MB process
    /// (design D8): the bytes are **mapped**, not copied onto the heap; the
    /// whole decode lives inside one `autoreleasepool` so the wire array and
    /// every temporary it allocated are gone the moment the projection exists;
    /// and the staged file is deleted immediately, since nothing downstream ever
    /// reads the raw payload again.
    ///
    /// Callers decode one resource at a time for the same reason — two mapped
    /// payloads alive at once would double the peak for no benefit.
    public static func decodeFormulae(
        contentsOf url: URL,
        deletingAfterwards: Bool = false
    ) throws -> DecodedResource {
        try project(url, deletingAfterwards: deletingAfterwards, using: decodeFormulae(from:))
    }

    public static func decodeCasks(
        contentsOf url: URL,
        deletingAfterwards: Bool = false
    ) throws -> DecodedResource {
        try project(url, deletingAfterwards: deletingAfterwards, using: decodeCasks(from:))
    }

    private static func project(
        _ url: URL,
        deletingAfterwards: Bool,
        using decode: (Data) throws -> DecodedResource
    ) throws -> DecodedResource {
        defer { if deletingAfterwards { try? FileManager.default.removeItem(at: url) } }
        return try autoreleasepool {
            let mapped: Data
            do {
                mapped = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw CatalogSyncError.malformedPayload
            }
            return try decode(mapped)
        }
    }

    // MARK: - Formulae

    static func formulaWireRecords(from data: Data) throws -> LossyArray<FormulaWire> {
        try decodeEnvelope(data)
    }

    public static func decodeFormulae(from data: Data) throws -> DecodedResource {
        let wire: LossyArray<FormulaWire> = try decodeEnvelope(data)
        let packages = wire.elements.compactMap(project(formula:))
        return try validated(
            DecodedResource(packages: packages, skippedRecordCount: wire.skippedCount)
        )
    }

    // MARK: - Casks

    static func caskWireRecords(from data: Data) throws -> LossyArray<CaskWire> {
        try decodeEnvelope(data)
    }

    public static func decodeCasks(from data: Data) throws -> DecodedResource {
        let wire: LossyArray<CaskWire> = try decodeEnvelope(data)
        let packages = wire.elements.compactMap(project(cask:))
        return try validated(
            DecodedResource(packages: packages, skippedRecordCount: wire.skippedCount)
        )
    }

    // MARK: - Envelope

    private static func decodeEnvelope<Element: Decodable>(
        _ data: Data
    ) throws -> LossyArray<Element> {
        do {
            return try JSONDecoder().decode(LossyArray<Element>.self, from: data)
        } catch {
            // The envelope itself was unreadable — not JSON at all, or not the
            // array the API documents. Nothing here is recoverable per record.
            throw CatalogSyncError.malformedPayload
        }
    }

    /// A resource that produced no usable record is treated as a failed fetch.
    ///
    /// This is the guard that stops a good snapshot from being replaced by an
    /// empty one after an origin-side accident (design D6).
    private static func validated(_ resource: DecodedResource) throws -> DecodedResource {
        guard !resource.packages.isEmpty else { throw CatalogSyncError.malformedPayload }
        return resource
    }

    // MARK: - Linking

    /// Joins the independently decoded resources into one snapshot.
    ///
    /// Cross-record facts can only be settled once every record is in hand, so
    /// they are settled exactly once here, at sync time, rather than per query:
    /// which declared dependencies actually resolve to a catalog package
    /// (package-detail PD2).
    public static func link(
        formulae: DecodedResource,
        casks: DecodedResource,
        analytics: AnalyticsIndex? = nil,
        generatedAt: Date
    ) -> CatalogSnapshot {
        // Only formulae can satisfy a formula's dependency edge.
        let formulaNames = Set(formulae.packages.map(\.name))

        let linkedFormulae = formulae.packages.map { package in
            package.replacingEdges(
                dependencies: resolve(package.dependencies, against: formulaNames),
                buildDependencies: resolve(package.buildDependencies, against: formulaNames),
                dependents: package.dependents
            )
        }

        var packages = linkedFormulae + casks.packages
        // An absent index means the analytics fetch failed. Leaving the carried
        // over counts alone is the graceful degradation: a stale count beats
        // wiping every number off the UI over one failed request.
        if let analytics {
            packages = packages.map { $0.replacingInstallCount(analytics.count(for: $0.id)) }
        }

        return CatalogSnapshot(
            generatedAt: generatedAt,
            skippedRecordCount: formulae.skippedRecordCount + casks.skippedRecordCount,
            packages: packages
        )
    }

    private static func resolve(
        _ edges: [PackageDependency],
        against names: Set<String>
    ) -> [PackageDependency] {
        edges.map { PackageDependency(name: $0.name, isResolvable: names.contains($0.name)) }
    }

    // MARK: - Projection

    static func project(formula: FormulaWire) -> CatalogPackage? {
        guard formula.tap == coveredTaps[.formula] else { return nil }

        let deprecated = formula.deprecated ?? false
        let disabled = formula.disabled ?? false

        return CatalogPackage(
            kind: .formula,
            name: formula.name,
            displayName: formula.name,
            desc: formula.desc,
            homepage: url(formula.homepage),
            license: formula.license,
            version: formula.versions?.stable ?? "",
            tap: formula.tap ?? "",
            dependencies: unlinked(formula.dependencies),
            buildDependencies: unlinked(formula.buildDependencies),
            dependents: [],
            caveats: formula.caveats,
            deprecated: deprecated,
            // A record that is merely *scheduled* for deprecation still carries
            // a date. Gating on the flag keeps "not deprecated" meaning exactly
            // that, with no reason and no date (package-detail PD4).
            deprecationReason: deprecated ? formula.deprecationReason : nil,
            deprecationDate: deprecated ? day(formula.deprecationDate) : nil,
            disabled: disabled,
            disableReason: disabled ? formula.disableReason : nil,
            disableDate: disabled ? day(formula.disableDate) : nil,
            autoUpdates: false,
            installCount365d: nil
        )
    }

    static func project(cask: CaskWire) -> CatalogPackage? {
        guard cask.tap == coveredTaps[.cask] else { return nil }

        let deprecated = cask.deprecated ?? false
        let disabled = cask.disabled ?? false

        return CatalogPackage(
            kind: .cask,
            name: cask.token,
            displayName: cask.displayName,
            desc: cask.desc,
            homepage: url(cask.homepage),
            license: nil,
            version: cask.version ?? "",
            tap: cask.tap ?? "",
            dependencies: [],
            buildDependencies: [],
            dependents: [],
            caveats: cask.caveats,
            deprecated: deprecated,
            deprecationReason: deprecated ? cask.deprecationReason : nil,
            deprecationDate: deprecated ? day(cask.deprecationDate) : nil,
            disabled: disabled,
            disableReason: disabled ? cask.disableReason : nil,
            disableDate: disabled ? day(cask.disableDate) : nil,
            autoUpdates: cask.autoUpdates ?? false,
            installCount365d: nil
        )
    }

    /// Dependency edges as declared, before the snapshot knows which resolve.
    private static func unlinked(_ names: [String]?) -> [PackageDependency] {
        (names ?? []).map { PackageDependency(name: $0, isResolvable: false) }
    }

    private static func url(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        return URL(string: string)
    }

    /// Parses the payload's `yyyy-MM-dd` dates.
    ///
    /// Fixed calendar, fixed zone, no locale: these are calendar days published
    /// by a build script, not user-facing timestamps.
    static func day(_ string: String?) -> Date? {
        guard let string else { return nil }
        return try? Date(string, strategy: dayStrategy)
    }

    private static let dayStrategy = Date.ISO8601FormatStyle(
        dateSeparator: .dash,
        timeZone: TimeZone(identifier: "UTC") ?? .gmt
    ).year().month().day()
}
