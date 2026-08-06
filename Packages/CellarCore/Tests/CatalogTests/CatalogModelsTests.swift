import Foundation
import Testing

@testable import Catalog

@Suite("Catalog domain models")
struct CatalogModelsTests {
    @Test("Identity is the (kind, name) pair, not the name alone")
    func identityIsKindAndName() {
        let formula = PackageID(kind: .formula, name: "docker")
        let cask = PackageID(kind: .cask, name: "docker")

        #expect(formula != cask)
        #expect(Set([formula, cask]).count == 2)
        #expect(formula == PackageID(kind: .formula, name: "docker"))
        #expect(formula.hashValue == PackageID(kind: .formula, name: "docker").hashValue)
    }

    @Test("A package's id carries the same kind it reports")
    func packageIDMatchesKind() {
        let package = CatalogPackage.stub(kind: .cask, name: "iterm2")
        #expect(package.id == PackageID(kind: .cask, name: "iterm2"))
        #expect(package.kind == .cask)
    }

    @Test("Deprecation and disable dates are modelled independently")
    func deprecationAndDisableDatesAreIndependent() {
        let deprecatedOn = Date(timeIntervalSince1970: 1_700_000_000)
        let disabledOn = Date(timeIntervalSince1970: 1_800_000_000)

        let package = CatalogPackage.stub(
            kind: .formula,
            name: "aamath",
            deprecated: true,
            deprecationReason: "unmaintained",
            deprecationDate: deprecatedOn,
            disabled: true,
            disableReason: "unmaintained",
            disableDate: disabledOn
        )

        #expect(package.deprecationDate == deprecatedOn)
        #expect(package.disableDate == disabledOn)
        #expect(package.deprecationDate != package.disableDate)
    }

    @Test("A dependency absent from the snapshot is listed but marked unresolvable")
    func unresolvableDependencyIsStillListed() {
        let resolvable = PackageDependency(name: "pcre2", isResolvable: true)
        let dangling = PackageDependency(name: "ghost-lib", isResolvable: false)

        let package = CatalogPackage.stub(
            kind: .formula,
            name: "git",
            dependencies: [resolvable, dangling]
        )

        #expect(package.dependencies.map(\.name) == ["pcre2", "ghost-lib"])
        #expect(package.dependencies.map(\.isResolvable) == [true, false])
    }

    @Test("An absent install count is not a count of zero")
    func absentCountIsNotZero() {
        let unreported = CatalogPackage.stub(kind: .formula, name: "obscure", installCount365d: nil)
        let zero = CatalogPackage.stub(kind: .formula, name: "quiet", installCount365d: 0)

        #expect(unreported.installCount == nil)
        #expect(zero.installCount?.value == 0)
    }

    @Test("A snapshot round-trips through Codable with its skipped-record tally")
    func snapshotRoundTrips() throws {
        let snapshot = CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            skippedRecordCount: 3,
            packages: [
                CatalogPackage.stub(kind: .formula, name: "wget"),
                CatalogPackage.stub(kind: .cask, name: "iterm2")
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CatalogSnapshot.self, from: data)

        #expect(decoded.packages.map(\.id) == snapshot.packages.map(\.id))
        #expect(decoded.skippedRecordCount == 3)
        #expect(decoded.schemaVersion == CatalogSnapshot.currentSchemaVersion)
    }

    // MARK: - Snapshot identity (D2)

    @Test("Revisions minted concurrently are unique and strictly increasing")
    func revisionsAreUniqueAndMonotonic() async {
        let sequential = (0..<3).map { _ in CatalogSnapshotRevision.next() }
        #expect(sequential[0].ordinal < sequential[1].ordinal)
        #expect(sequential[1].ordinal < sequential[2].ordinal)

        let minted = await withTaskGroup(of: CatalogSnapshotRevision.self) { group in
            for _ in 0..<200 { group.addTask { CatalogSnapshotRevision.next() } }
            return await group.reduce(into: [CatalogSnapshotRevision]()) { $0.append($1) }
        }

        #expect(minted.count == 200)
        #expect(Set(minted).count == 200, "two concurrent callers were handed the same revision")
    }

    @Test("Two decodes of the same bytes are two distinct materializations")
    func decodingMintsAFreshRevision() throws {
        let snapshot = CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            skippedRecordCount: 0,
            packages: [CatalogPackage.stub(kind: .formula, name: "wget")]
        )
        let data = try JSONEncoder().encode(snapshot)

        let first = try JSONDecoder().decode(CatalogSnapshot.self, from: data)
        let second = try JSONDecoder().decode(CatalogSnapshot.self, from: data)

        #expect(first.revision != second.revision)
        #expect(first.revision != snapshot.revision)
        #expect(first.packages.map(\.id) == second.packages.map(\.id))
    }

    @Test("The persisted JSON gains no key: identity is process-local only")
    func revisionIsNotPersisted() throws {
        let snapshot = CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            skippedRecordCount: 3,
            packages: [CatalogPackage.stub(kind: .formula, name: "wget")]
        )

        let data = try JSONEncoder().encode(snapshot)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(
            Set(object.keys) == ["schemaVersion", "generatedAt", "skippedRecordCount", "packages"]
        )
        // The version moves only when the persisted *shape* moves — which M5's
        // two new package fields did, hence 2 rather than 1. `revision` still
        // adds no key: that is what the four-key set above proves.
        #expect(object["schemaVersion"] as? Int == 2)
        #expect(object["schemaVersion"] as? Int == CatalogSnapshot.currentSchemaVersion)
    }

    // MARK: - The copy helpers enumerate every field by hand (M5)

    /// `replacingEdges` and `replacingInstallCount` each rewrite all twenty-odd
    /// fields by name. Adding a field to `CatalogPackage` without adding it to
    /// both is a silent drop that no compiler diagnostic catches and no other
    /// test would notice — the package would simply lose its inspection somewhere
    /// between decode and snapshot. This is that test.
    @Test("Inspection fields survive both full-field copy helpers")
    func inspectionSurvivesTheCopyHelpers() {
        let inspection = CaskInspection(
            downloadURL: "https://example.invalid/x.dmg",
            declaredChecksum: .declared("abc123"),
            installPlan: CaskInstallPlan(
                apps: [CaskInstallArtifact(source: "X.app", target: "/Applications/X.app")],
                binaries: [],
                packageInstallers: [],
                unrepresentedStanzaCount: 2
            ),
            requirements: CaskRequirements(
                formulae: ["git"], casks: [], macOSRequirement: ">= 13", unrepresentedCount: 0
            ),
            conflicts: CaskConflicts(casks: ["x@beta"], formulae: [], unrepresentedCount: 0)
        )
        let sources = FormulaSources(
            stableURL: "https://example.invalid/x.tar.gz", headURL: "https://example.invalid/x.git"
        )
        let package = CatalogPackage.stub(
            kind: .cask,
            name: "x",
            caskInspection: inspection,
            formulaSources: sources
        )

        let relinked = package.replacingEdges(
            dependencies: [PackageDependency(name: "git", isResolvable: true)],
            buildDependencies: [],
            dependents: ["y"]
        )
        // The edges really were replaced, so the copy is a real one.
        #expect(relinked.dependencies.map(\.name) == ["git"])
        #expect(relinked.dependents == ["y"])
        #expect(relinked.caskInspection == inspection)
        #expect(relinked.formulaSources == sources)

        let counted = relinked.replacingInstallCount(4_200)
        #expect(counted.installCount365d == 4_200)
        #expect(counted.caskInspection == inspection)
        #expect(counted.formulaSources == sources)
        // Every unrelated field the second helper also rewrites by hand.
        #expect(counted.dependents == ["y"])
        #expect(counted.name == "x")
    }

    @Test("A package carrying inspection round-trips through the persisted projection")
    func inspectionRoundTripsThroughCodable() throws {
        let package = CatalogPackage.stub(
            kind: .cask,
            name: "x",
            caskInspection: CaskInspection(
                downloadURL: "https://example.invalid/x.dmg",
                declaredChecksum: .notChecked,
                installPlan: CaskInstallPlan(
                    apps: [CaskInstallArtifact(source: "X.app", target: nil)],
                    binaries: [],
                    packageInstallers: [],
                    unrepresentedStanzaCount: 1
                ),
                requirements: nil,
                conflicts: nil
            )
        )

        let decoded = try JSONDecoder().decode(
            CatalogPackage.self, from: JSONEncoder().encode(package)
        )

        #expect(decoded == package)
        #expect(decoded.caskInspection?.declaredChecksum == .notChecked)
        #expect(decoded.caskInspection?.installPlan?.unrepresentedStanzaCount == 1)
        // A package that carries no inspection stays absent, not empty.
        let bare = CatalogPackage.stub(kind: .formula, name: "wget")
        let decodedBare = try JSONDecoder().decode(
            CatalogPackage.self, from: JSONEncoder().encode(bare)
        )
        #expect(decodedBare.caskInspection == nil)
        #expect(decodedBare.formulaSources == nil)
    }
}

extension CatalogPackage {
    /// Builds a package with everything defaulted, so each test names only the
    /// fields it actually asserts on.
    static func stub(
        kind: PackageKind,
        name: String,
        displayName: String? = nil,
        desc: String? = nil,
        homepage: URL? = nil,
        license: String? = nil,
        version: String = "1.0.0",
        tap: String? = nil,
        dependencies: [PackageDependency] = [],
        buildDependencies: [PackageDependency] = [],
        dependents: [String] = [],
        caveats: String? = nil,
        deprecated: Bool = false,
        deprecationReason: String? = nil,
        deprecationDate: Date? = nil,
        disabled: Bool = false,
        disableReason: String? = nil,
        disableDate: Date? = nil,
        autoUpdates: Bool = false,
        installCount365d: Int? = nil,
        caskInspection: CaskInspection? = nil,
        formulaSources: FormulaSources? = nil
    ) -> CatalogPackage {
        CatalogPackage(
            kind: kind,
            name: name,
            displayName: displayName ?? name,
            desc: desc,
            homepage: homepage,
            license: license,
            version: version,
            tap: tap ?? (kind == .formula ? "homebrew/core" : "homebrew/cask"),
            dependencies: dependencies,
            buildDependencies: buildDependencies,
            dependents: dependents,
            caveats: caveats,
            deprecated: deprecated,
            deprecationReason: deprecationReason,
            deprecationDate: deprecationDate,
            disabled: disabled,
            disableReason: disableReason,
            disableDate: disableDate,
            autoUpdates: autoUpdates,
            installCount365d: installCount365d,
            caskInspection: caskInspection,
            formulaSources: formulaSources
        )
    }
}
