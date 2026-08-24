import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The tap, installed and catalog shapes the composed tap-search rows read.
///
/// Extends the shipped fixtures rather than replacing them: every installed
/// record comes from `InstalledFixture.receipt`, so "installed" means here
/// exactly what it already means in `TapProjectionTests`, and every shipped
/// signature stays source-compatible.
enum TapSearchFixture {
    // MARK: - Taps

    static func tap(
        _ name: String,
        formulae: [String] = [],
        casks: [String] = [],
        trust: TapTrustState = .unreported
    ) -> TapRecord {
        TapRecord(
            name: name,
            repository: name.split(separator: "/").last.map(String.init) ?? name,
            formulaNames: formulae,
            caskTokens: casks,
            trust: trust
        )
    }

    static func inventory(_ taps: [TapRecord]) -> TapInventory {
        TapInventory(taps: taps)
    }

    /// The three tokens the rank ladder is read off: one exact, one prefix, one
    /// substring, all published by one third-party tap.
    static let acmeWidgets = tap(
        "acme/tools",
        formulae: [
            "acme/tools/widget",
            "acme/tools/widget-cli",
            "acme/tools/superwidget"
        ]
    )

    /// The hyphenated token DD-3's token-awareness is keyed to: `gentle-ai`
    /// normalises to the two tokens `gentle ai`, and its published name to
    /// `gentleman programming tap gentle ai`.
    static let gentlemanTap = tap(
        "gentleman-programming/tap",
        formulae: ["gentleman-programming/tap/gentle-ai"]
    )

    /// Two taps, each publishing a formula **and** a cask on the same bare
    /// token — the fixture that makes the order's fourth key load-bearing.
    static let acmeBothKinds = tap(
        "acme/tools",
        formulae: ["acme/tools/widget"],
        casks: ["acme/tools/widget"]
    )
    static let bravoBothKinds = tap(
        "bravo/tools",
        formulae: ["bravo/tools/widget"],
        casks: ["bravo/tools/widget"]
    )

    /// A tap publishing a bare token the catalog also carries.
    static let acmeWget = tap("acme/tools", formulae: ["acme/tools/wget"])

    /// An official tap. Excluded by `TapProjection.officialNames`, and named
    /// here so the exclusion is proven against a record that really is present.
    static let officialCore = tap("homebrew/core", formulae: ["wget"])
    static let officialCask = tap("homebrew/cask", casks: ["visual-studio-code"])

    /// One tap publishing forty packages, for the empty-query rows.
    static let acmeForty = tap(
        "acme/tools",
        formulae: (0..<40).map { "acme/tools/pkg\($0)" }
    )

    // MARK: - The three install states

    /// Installed, with its tap known.
    static let stateInstalledTap = tap("acme/tools", formulae: ["acme/tools/widget-installed"])
    /// Installed, with the tap withheld under an `untrusted` publishing tap.
    static let stateWithheldTap = tap(
        "bravo/tools",
        formulae: ["bravo/tools/widget-withheld"],
        trust: .untrusted
    )
    /// Published, never installed.
    static let stateAbsentTap = tap("carol/tools", formulae: ["carol/tools/widget-absent"])

    static let threeStateTaps = [stateInstalledTap, stateWithheldTap, stateAbsentTap]

    static var threeStateInstalled: InstalledInventory {
        InstalledInventory(packages: [
            InstalledFixture.receipt(.formula, "widget-installed", tap: "acme/tools"),
            InstalledFixture.receipt(.formula, "widget-withheld", tap: nil)
        ])
    }

    // MARK: - Two taps, one identity, both installed

    /// Both publishing taps are `untrusted` and the one installed record has no
    /// tap, so **both** hits resolve to the middle state and carry the same
    /// `PackageID` — the duplicate-identity cause `alsoInCatalog` cannot see.
    static let acmeDuplicate = tap(
        "acme/tools",
        formulae: ["acme/tools/widget"],
        trust: .untrusted
    )
    static let bravoDuplicate = tap(
        "bravo/tools",
        formulae: ["bravo/tools/widget"],
        trust: .untrusted
    )

    static var withheldWidgetInstalled: InstalledInventory {
        InstalledInventory(packages: [InstalledFixture.receipt(.formula, "widget", tap: nil)])
    }

    static var acmeWidgetInstalled: InstalledInventory {
        InstalledInventory(packages: [
            InstalledFixture.receipt(.formula, "widget", tap: "acme/tools")
        ])
    }

    // MARK: - Catalog

    static func catalogPackage(
        _ kind: PackageKind,
        _ name: String,
        desc: String? = nil,
        installCount: Int? = nil
    ) -> CatalogPackage {
        CatalogPackage(
            kind: kind, name: name, displayName: name, desc: desc, homepage: nil,
            license: nil, version: "1.0.0",
            tap: kind == .formula ? "homebrew/core" : "homebrew/cask",
            dependencies: [], buildDependencies: [], dependents: [], caveats: nil,
            deprecated: false, deprecationReason: nil, deprecationDate: nil,
            disabled: false, disableReason: nil, disableDate: nil, autoUpdates: false,
            installCount365d: installCount
        )
    }

    static func snapshot(_ packages: [CatalogPackage]) -> CatalogSnapshot {
        CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            skippedRecordCount: 0,
            packages: packages
        )
    }

    /// A real index, built the way the shipped catalog builds one.
    static func index(_ packages: [CatalogPackage]) -> PackageSearchIndex {
        PackageSearchIndex(snapshot: snapshot(packages))
    }

    // MARK: - Tap load states

    static let brewAbsent = TapLoadState.brewAbsent(.notInstalled(.standard))
    static let refreshFailed = TapLoadState.failed(.commandFailed(status: 1, message: "boom"))
}
