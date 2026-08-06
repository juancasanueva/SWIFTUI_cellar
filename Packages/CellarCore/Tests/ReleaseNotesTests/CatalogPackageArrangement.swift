import Catalog
import Foundation

/// Builds the one `Catalog` type this target reads.
///
/// `CatalogPackage` has a hand-written twenty-two-parameter initialiser, and the
/// four fields release notes cares about are three of them deep. A helper keeps
/// each test naming only the fields under test — which is what makes "a formula
/// resolvable *only* through `urls.stable`" legible as a sentence rather than as
/// nineteen `nil`s with one URL hidden in the middle.
enum CatalogPackageArrangement {
    static func formula(
        name: String = "foo",
        homepage: String? = nil,
        stableURL: String? = nil,
        headURL: String? = nil,
        version: String = "1.2.0"
    ) -> CatalogPackage {
        package(
            kind: .formula,
            name: name,
            homepage: homepage,
            version: version,
            formulaSources: stableURL == nil && headURL == nil
                ? nil
                : FormulaSources(stableURL: stableURL, headURL: headURL)
        )
    }

    static func cask(
        name: String = "tool",
        homepage: String? = nil,
        downloadURL: String? = nil,
        version: String = "3.0"
    ) -> CatalogPackage {
        package(
            kind: .cask,
            name: name,
            homepage: homepage,
            version: version,
            caskInspection: downloadURL == nil
                ? nil
                : CaskInspection(
                    downloadURL: downloadURL,
                    declaredChecksum: nil,
                    installPlan: nil,
                    requirements: nil,
                    conflicts: nil
                )
        )
    }

    private static func package(
        kind: PackageKind,
        name: String,
        homepage: String?,
        version: String,
        caskInspection: CaskInspection? = nil,
        formulaSources: FormulaSources? = nil
    ) -> CatalogPackage {
        CatalogPackage(
            kind: kind,
            name: name,
            displayName: name,
            desc: nil,
            homepage: homepage.flatMap(URL.init(string:)),
            license: nil,
            version: version,
            tap: kind == .formula ? "homebrew/core" : "homebrew/cask",
            dependencies: [],
            buildDependencies: [],
            dependents: [],
            caveats: nil,
            deprecated: false,
            deprecationReason: nil,
            deprecationDate: nil,
            disabled: false,
            disableReason: nil,
            disableDate: nil,
            autoUpdates: false,
            installCount365d: nil,
            caskInspection: caskInspection,
            formulaSources: formulaSources
        )
    }
}
