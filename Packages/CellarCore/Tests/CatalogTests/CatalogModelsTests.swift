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
        installCount365d: Int? = nil
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
            installCount365d: installCount365d
        )
    }
}
