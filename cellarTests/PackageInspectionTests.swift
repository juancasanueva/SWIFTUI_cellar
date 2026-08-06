//
//  PackageInspectionTests.swift
//  cellarTests
//

import Catalog
import Foundation
import Testing

@testable import cellar

/// The always-visible cask inspection section (D4).
///
/// Two claims, tested two ways. The **row model** is a plain value type, so what
/// the section says about a package is provable without rendering anything —
/// which is why the formatting lives there and not inside `body`. The **source
/// scan** covers what a value type cannot: that the file carries no verdict
/// vocabulary and constructs no `URL` of its own.
@Suite("Package inspection section")
struct PackageInspectionTests {
    // MARK: - Arrangement

    static func cask(
        name: String = "iterm2",
        downloadURL: String? = "https://iterm2.com/downloads/stable/iTerm2-3_6_11.zip",
        checksum: CaskDownloadChecksum? = .declared("36e78c50"),
        plan: CaskInstallPlan? = CaskInstallPlan(
            apps: [CaskInstallArtifact(source: "iTerm.app", target: "/Applications/iTerm.app")],
            binaries: [],
            packageInstallers: [],
            unrepresentedStanzaCount: 1
        ),
        requirements: CaskRequirements? = CaskRequirements(
            formulae: [], casks: [], macOSRequirement: ">= 12", unrepresentedCount: 0
        ),
        conflicts: CaskConflicts? = CaskConflicts(
            casks: ["iterm2@beta", "iterm2@nightly"], formulae: [], unrepresentedCount: 0
        )
    ) -> CatalogPackage {
        CatalogPackage(
            kind: .cask,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            license: nil,
            version: "3.6.11",
            tap: "homebrew/cask",
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
            autoUpdates: true,
            installCount365d: nil,
            caskInspection: CaskInspection(
                downloadURL: downloadURL,
                declaredChecksum: checksum,
                installPlan: plan,
                requirements: requirements,
                conflicts: conflicts
            )
        )
    }

    static func identifiers(_ rows: [PackageInspectionRow]) -> [String] {
        rows.map(\.identifier)
    }

    // MARK: - A row per present value, and no row for an absent one (R8)

    @Test("A fully published cask yields one row per published value")
    func fullyPublishedCaskYieldsEveryRow() throws {
        let rows = PackageInspectionRow.rows(for: Self.cask())

        #expect(
            Self.identifiers(rows) == [
                "inspection-download",
                "inspection-checksum",
                "inspection-installs",
                "inspection-remainder",
                "inspection-requires",
                "inspection-conflicts"
            ]
        )

        let download = try #require(rows.first { $0.identifier == "inspection-download" })
        #expect(download.value == "https://iterm2.com/downloads/stable/iTerm2-3_6_11.zip")
        // Only an http(s) URL becomes a link, and it comes from CellarCore.
        #expect(download.link == URL(string: "https://iterm2.com/downloads/stable/iTerm2-3_6_11.zip"))

        let installs = try #require(rows.first { $0.identifier == "inspection-installs" })
        #expect(installs.value == "Installs iTerm.app into /Applications/iTerm.app")

        let remainder = try #require(rows.first { $0.identifier == "inspection-remainder" })
        #expect(remainder.value == "1 other install step isn’t shown here")
    }

    @Test("An absent value yields no row at all")
    func absentValuesYieldNoRow() {
        let bare = PackageInspectionRow.rows(
            for: Self.cask(
                downloadURL: nil, checksum: nil, plan: nil, requirements: nil, conflicts: nil
            )
        )

        #expect(bare.isEmpty)

        // ...and each absence is independent: dropping one leaves the others.
        let noConflicts = PackageInspectionRow.rows(for: Self.cask(conflicts: nil))
        #expect(Self.identifiers(noConflicts).contains("inspection-conflicts") == false)
        #expect(Self.identifiers(noConflicts).contains("inspection-download"))
        #expect(Self.identifiers(noConflicts).contains("inspection-requires"))

        // A formula has no inspection at all, so the section renders nothing.
        let formula = CatalogPackage(
            kind: .formula, name: "wget", displayName: "wget", desc: nil, homepage: nil,
            license: nil, version: "1.25.0", tap: "homebrew/core", dependencies: [],
            buildDependencies: [], dependents: [], caveats: nil, deprecated: false,
            deprecationReason: nil, deprecationDate: nil, disabled: false, disableReason: nil,
            disableDate: nil, autoUpdates: false, installCount365d: nil
        )
        #expect(PackageInspectionRow.rows(for: formula).isEmpty)
    }

    @Test("The remainder line appears only when something was not shown")
    func remainderAppearsOnlyWhenSomethingWasNotShown() throws {
        let none = PackageInspectionRow.rows(
            for: Self.cask(
                plan: CaskInstallPlan(
                    apps: [CaskInstallArtifact(source: "iTerm.app", target: nil)],
                    binaries: [],
                    packageInstallers: [],
                    unrepresentedStanzaCount: 0
                )
            )
        )
        #expect(Self.identifiers(none).contains("inspection-remainder") == false)
        // The install row is still there, so the absence above is the remainder's
        // and not the whole plan's.
        #expect(Self.identifiers(none).contains("inspection-installs"))

        let several = PackageInspectionRow.rows(
            for: Self.cask(
                plan: CaskInstallPlan(
                    apps: [], binaries: [], packageInstallers: [], unrepresentedStanzaCount: 4
                )
            )
        )
        let remainder = try #require(several.first { $0.identifier == "inspection-remainder" })
        // Phrased as install steps that are not shown — never as a stanza count,
        // and never as a claim about what those steps do.
        #expect(remainder.value == "4 other install steps aren’t shown here")
        #expect(Self.identifiers(several).contains("inspection-installs") == false)
    }

    @Test("The checksum row states a declaration, and no_check is not a digest")
    func checksumRowStatesADeclaration() throws {
        let declared = try #require(
            PackageInspectionRow.rows(for: Self.cask())
                .first { $0.identifier == "inspection-checksum" }
        )
        #expect(declared.value == "36e78c50")
        #expect(
            declared.note
                == "The value this cask declares. Cellar has not downloaded or checked anything."
        )

        let notChecked = try #require(
            PackageInspectionRow.rows(for: Self.cask(checksum: .notChecked))
                .first { $0.identifier == "inspection-checksum" }
        )
        #expect(notChecked.value == "This cask declares no checksum")
        #expect(notChecked.value.contains("no_check") == false)
    }

    @Test("Every projected stanza kind reads as plain language")
    func everyStanzaKindReadsAsPlainLanguage() throws {
        let rows = PackageInspectionRow.rows(
            for: Self.cask(
                plan: CaskInstallPlan(
                    apps: [
                        CaskInstallArtifact(source: "iTerm.app", target: nil),
                        CaskInstallArtifact(source: "Extra.app", target: "/Users/x/Apps/Extra.app")
                    ],
                    binaries: [CaskInstallArtifact(source: "bin/iterm", target: "iterm")],
                    packageInstallers: [CaskInstallArtifact(source: "iTerm.pkg", target: nil)],
                    unrepresentedStanzaCount: 0
                )
            )
        )

        let installs = try #require(rows.first { $0.identifier == "inspection-installs" })
        #expect(
            installs.detail == [
                // An app with no published destination lands in the folder
                // Homebrew uses — a CellarCore fact, not a view guess.
                "Installs iTerm.app into /Applications",
                "Installs Extra.app into /Users/x/Apps/Extra.app",
                "Adds the command iterm",
                "Runs the installer package iTerm.pkg"
            ]
        )
    }

    @Test("Requirements and conflicts name what the record named")
    func requirementsAndConflictsNameWhatWasPublished() throws {
        let rows = PackageInspectionRow.rows(
            for: Self.cask(
                requirements: CaskRequirements(
                    formulae: ["git"],
                    casks: ["xquartz"],
                    macOSRequirement: ">= 13",
                    unrepresentedCount: 0
                )
            )
        )

        let requires = try #require(rows.first { $0.identifier == "inspection-requires" })
        #expect(requires.detail == ["macOS >= 13", "The formula git", "The cask xquartz"])

        let conflicts = try #require(rows.first { $0.identifier == "inspection-conflicts" })
        #expect(conflicts.detail == ["The cask iterm2@beta", "The cask iterm2@nightly"])
    }

    // MARK: - What may become a link (TM2)

    @Test(
        "A download URL that is not http or https renders as text, never as a link",
        arguments: [
            "javascript:alert(1)", "file:///etc/passwd", "data:text/html,x",
            "ftp://example.invalid/x.dmg", "example.com/x.dmg"
        ]
    )
    func hostileDownloadURLsAreNotLinked(published: String) throws {
        let row = try #require(
            PackageInspectionRow.rows(for: Self.cask(downloadURL: published))
                .first { $0.identifier == "inspection-download" }
        )

        // Shown, because dropping a published fact is its own kind of lie...
        #expect(row.value == published)
        // ...but never handed to something that would open it.
        #expect(row.link == nil)
    }

    // MARK: - Source scan (TM1, TM2, TM3)

    static let fileName = "PackageInspectionSection.swift"

    static func sectionCode() throws -> String {
        let source = try #require(
            try AppSecuritySources.load().first { $0.name == fileName },
            "the scan did not find \(fileName) in the app target"
        )
        #expect(source.code.isEmpty == false)
        return source.code
    }

    @Test("The section speaks no verdict vocabulary and runs nothing")
    func theSectionSpeaksNoVerdictVocabulary() throws {
        let code = try Self.sectionCode()
        // Anchored: a scan that read the wrong file would fail here rather than
        // pass every absence below.
        #expect(code.contains("PackageInspectionRow"))

        for forbidden in [
            "signature", "notariz", "verified", "trust", "safe", "malware", "secure"
        ] {
            #expect(
                code.lowercased().contains(forbidden) == false,
                "\(Self.fileName) says \(forbidden)"
            )
        }
        for forbidden in ["Process", "OperationCenter", "MutationCommand", "removeItem"] {
            #expect(code.contains(forbidden) == false, "\(Self.fileName) references \(forbidden)")
        }
    }

    @Test("The section builds a URL only through the CellarCore predicate")
    func theSectionBuildsNoURLOfItsOwn() throws {
        let code = try Self.sectionCode()

        // `browsableDownloadURL` is the *only* way catalog text becomes a URL
        // here. A bare `URL(string:)` on a published value is precisely the bug
        // this forbids, so the token is banned outright rather than inspected.
        #expect(code.contains("browsableDownloadURL"))
        #expect(code.contains("URL(string:") == false, "\(Self.fileName) builds a URL of its own")
        #expect(code.contains("URL(fileURLWithPath:") == false)
        #expect(code.contains("NSWorkspace") == false)
        #expect(code.contains("openURL") == false)
    }

    @Test("The section declares every identifier the detail view is specified on")
    func theSectionDeclaresEveryIdentifier() throws {
        let code = try Self.sectionCode()

        for identifier in [
            "inspection-download", "inspection-checksum", "inspection-installs",
            "inspection-requires", "inspection-conflicts", "inspection-remainder"
        ] {
            #expect(code.contains(identifier), "\(Self.fileName) declares no \(identifier)")
        }
    }

    @Test("The detail view renders the section for casks, and not behind a disclosure")
    func theDetailViewRendersTheSection() throws {
        let detail = try #require(
            try AppSecuritySources.load().first { $0.name == "PackageDetailView.swift" }
        )

        #expect(detail.code.contains("PackageInspectionSection("))
        // Always visible (D4): no disclosure wraps it.
        #expect(detail.code.contains("DisclosureGroup") == false)
    }
}
