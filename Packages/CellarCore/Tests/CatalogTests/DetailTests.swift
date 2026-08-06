import Foundation
import Testing

@testable import Catalog

@Suite("Detail resolution")
struct DetailTests {
    static func index() throws -> PackageSearchIndex {
        PackageSearchIndex(snapshot: try DependentsTests.fixtureSnapshot())
    }

    /// The slice fixtures deliberately have `artifacts`, `sha256` and `urls`
    /// stripped, so inspection is resolved against the verbatim single-record
    /// fixtures instead — through the same link-then-index path a real sync uses.
    static func inspectionIndex(
        casks: [String],
        formulae: [String] = ["formula-git"]
    ) throws -> PackageSearchIndex {
        PackageSearchIndex(
            snapshot: CatalogDecoder.link(
                formulae: try CatalogDecoder.decodeFormulae(from: Fixture.arrayOf(formulae)),
                casks: try CatalogDecoder.decodeCasks(from: Fixture.arrayOf(casks)),
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
    }

    static func cask(_ name: String, from fixtures: [String]) throws -> CatalogPackage {
        try #require(
            try inspectionIndex(casks: fixtures).package(PackageID(kind: .cask, name: name))
        )
    }

    @Test("An unknown package resolves to not-found without throwing")
    func unknownPackageIsNotFound() throws {
        let index = try Self.index()

        #expect(index.package(PackageID(kind: .formula, name: "nosuchpackage")) == nil)
        // The same index does resolve a package it holds, so the nil above is a
        // real miss and not an empty index.
        #expect(index.package(PackageID(kind: .formula, name: "wget"))?.name == "wget")
    }

    @Test("A name in the wrong namespace is a miss, not a silent cross-namespace hit")
    func wrongNamespaceIsAMiss() throws {
        let index = try Self.index()

        #expect(index.package(PackageID(kind: .cask, name: "wget")) == nil)
        #expect(index.package(PackageID(kind: .formula, name: "iterm2")) == nil)
        #expect(index.package(PackageID(kind: .cask, name: "iterm2"))?.displayName == "iTerm2")
    }

    @Test("A third-party tap package is an ordinary not-found after a successful sync")
    func thirdPartyTapIsNotFound() async throws {
        let harness = try SyncHarness()
        let payload = Data(#"""
        [{"name":"wget","tap":"homebrew/core","desc":"Internet file retriever",
          "versions":{"stable":"1.25.0"}},
         {"name":"privatetool","tap":"acme/internal","desc":"private",
          "versions":{"stable":"9.9.9"}}]
        """#.utf8)
        harness.source.script(.payload(payload), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        let result = await harness.engine.sync()

        let snapshot = try #require(result.value)
        let index = PackageSearchIndex(snapshot: snapshot)
        #expect(index.package(PackageID(kind: .formula, name: "privatetool")) == nil)
        #expect(index.search("privatetool").isEmpty)
        // Absence is not a failure state.
        #expect(await harness.engine.status == .succeeded(at: harness.time.now))
        #expect(index.package(PackageID(kind: .formula, name: "wget")) != nil)
    }

    @Test("The resolved detail carries every PD1 field for a real formula")
    func formulaDetailIsComplete() throws {
        let index = try Self.index()
        let git = try #require(index.package(PackageID(kind: .formula, name: "git")))

        #expect(git.displayName == "git")
        #expect(git.kind == .formula)
        #expect(git.desc?.isEmpty == false)
        #expect(git.homepage != nil)
        // SPDX expressions are carried verbatim, not parsed into a single id.
        #expect(git.license?.hasPrefix("GPL-2.0-only AND ") == true)
        #expect(git.version.isEmpty == false)
        #expect(git.tap == "homebrew/core")
        #expect(git.dependencies.map(\.name) == ["pcre2", "gettext"])
        #expect(git.buildDependencies.map(\.name) == ["gettext", "pkgconf"])
        #expect(git.deprecated == false)
        #expect(git.disabled == false)
    }

    @Test("Absent optional fields stay absent through detail resolution")
    func absentFieldsStayAbsent() throws {
        let index = try Self.index()
        let iterm = try #require(index.package(PackageID(kind: .cask, name: "iterm2")))

        #expect(iterm.caveats == nil)
        #expect(iterm.license == nil)
        #expect(iterm.desc != nil)
        #expect(iterm.caveats != "")
    }

    // MARK: - Cask inspection (R5)

    @Test("A cask detail exposes every inspection field its record published")
    func caskDetailExposesItsInspectionFields() throws {
        let iterm = try Self.cask("iterm2", from: ["cask-iterm2"])
        let inspection = try #require(iterm.caskInspection)

        #expect(inspection.downloadURL == "https://iterm2.com/downloads/stable/iTerm2-3_6_11.zip")
        #expect(
            inspection.declaredChecksum
                == .declared("36e78c5049560eaa8e122224f6652eb4b229c61cd5e7332d6d25b5c36f7398e7")
        )
        #expect(
            inspection.installPlan?.apps
                == [CaskInstallArtifact(source: "iTerm.app", target: "/Applications/iTerm.app")]
        )
        #expect(inspection.requirements?.macOSRequirement == ">= 12")
        #expect(inspection.conflicts?.casks == ["iterm2@beta", "iterm2@nightly"])
        #expect(iterm.autoUpdates)

        // The `zap` stanza is not exposed. It appears only as this number.
        #expect(inspection.installPlan?.unrepresentedStanzaCount == 1)
        #expect(inspection.installPlan?.binaries.isEmpty == true)
        #expect(inspection.installPlan?.packageInstallers.isEmpty == true)
    }

    // MARK: - The projected stanza set and its remainder (R6, R7, R8, R9)

    @Test("Every projected stanza kind is exposed with its name and destination")
    func everyProjectedStanzaKindIsExposed() throws {
        let plan = try #require(
            try Self.cask("every-stanza", from: ["cask-every-stanza"]).caskInspection?.installPlan
        )

        #expect(
            plan.apps == [
                CaskInstallArtifact(
                    source: "Every Stanza.app", target: "/Applications/Every Stanza.app"
                )
            ]
        )
        #expect(
            plan.binaries == [
                CaskInstallArtifact(
                    source: "Every Stanza.app/Contents/MacOS/every-stanza", target: "every-stanza"
                )
            ]
        )
        #expect(plan.packageInstallers == [CaskInstallArtifact(source: "EveryStanza.pkg", target: nil)])
        // `uninstall` + `zap`.
        #expect(plan.unrepresentedStanzaCount == 2)
    }

    @Test("An unprojected stanza kind is counted, and counted separately from skipped records")
    func unprojectedStanzaKindsAreCounted() throws {
        let index = try Self.inspectionIndex(
            casks: ["cask-unrepresented", "cask-only-unrepresented"]
        )

        let mixed = try #require(index.package(PackageID(kind: .cask, name: "unrepresented")))
        let mixedPlan = try #require(mixed.caskInspection?.installPlan)
        #expect(mixedPlan.apps.map(\.source) == ["Unrepresented.app"])
        #expect(mixedPlan.unrepresentedStanzaCount == 3)

        let only = try #require(index.package(PackageID(kind: .cask, name: "only-unrepresented")))
        let onlyPlan = try #require(only.caskInspection?.installPlan)
        #expect(onlyPlan.apps.isEmpty)
        #expect(onlyPlan.binaries.isEmpty)
        #expect(onlyPlan.packageInstallers.isEmpty)
        #expect(onlyPlan.unrepresentedStanzaCount > 0)

        // The remainder is a property of the record; the snapshot's skipped
        // tally is a property of the payload. Both records decoded fine.
        let snapshot = CatalogDecoder.link(
            formulae: try CatalogDecoder.decodeFormulae(from: Fixture.arrayOf(["formula-git"])),
            casks: try CatalogDecoder.decodeCasks(
                from: Fixture.arrayOf(["cask-unrepresented", "cask-only-unrepresented"])
            ),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(snapshot.skippedRecordCount == 0)
    }

    @Test("A cask publishing no widened key reports absence, not emptiness")
    func absentInspectionIsNotEmptyInspection() throws {
        let bare = try Self.cask("bare", from: ["cask-bare", "cask-bare-null"])
        let bareNull = try Self.cask("bare-null", from: ["cask-bare", "cask-bare-null"])

        for record in [bare, bareNull] {
            // The whole group is absent, which is what makes absence cheap.
            #expect(record.caskInspection == nil, "\(record.name) must carry no inspection")
            // ...and every other required field resolved anyway.
            #expect(record.version == "1.0")
            #expect(record.tap == "homebrew/cask")
            #expect(record.desc?.isEmpty == false)
            #expect(record.autoUpdates)
        }

        // A cask that published *some* widened key keeps the group, and only the
        // unpublished members inside it are absent.
        let partial = try Self.cask("no-check", from: ["cask-no-check"])
        let inspection = try #require(partial.caskInspection)
        #expect(inspection.declaredChecksum == .notChecked)
        #expect(inspection.requirements == nil)
        #expect(inspection.conflicts == nil)
        #expect(inspection.installPlan?.apps.map(\.source) == ["No Check.app"])
    }

    // MARK: - What the projection cannot say (N1, N2, N3, TM3)

    /// Vocabulary a pre-install surface must not be able to speak. Catalog data
    /// supports no claim about a download's signature, notarization or origin
    /// identity, so the prohibition is enforced by the projection's *shape* —
    /// there is no field to render — rather than by a consumer's discipline.
    static let verdictVocabulary = [
        "signature", "signing", "signed", "notariz", "verified", "verification",
        "trust", "trusted", "teamIdentifier", "certificate", "integrity",
        "quarantine", "assessment", "codesign"
    ]

    @Test("A fully populated cask detail exposes no verdict-bearing field")
    func fullyPopulatedCaskDetailMakesNoSignatureClaim() throws {
        let iterm = try Self.cask("iterm2", from: ["cask-iterm2"])
        let labels = ExposedFields.labels(of: iterm)

        // The enumeration really walked the record, inspection included.
        #expect(labels.contains("caskInspection"))
        #expect(labels.contains("downloadURL"))
        #expect(labels.contains("declaredChecksum"))
        #expect(labels.contains("unrepresentedStanzaCount"))
        #expect(labels.count > 20, "the reflection walk found only \(labels.count) fields")

        for forbidden in Self.verdictVocabulary {
            #expect(
                labels.contains { $0.lowercased().contains(forbidden.lowercased()) } == false,
                "a detail field names \(forbidden)"
            )
        }
    }

    @Test("The checksum is the expectation the record declares, never a result")
    func checksumIsADeclarationNotAResult() throws {
        let declared = try #require(
            try Self.cask("iterm2", from: ["cask-iterm2"]).caskInspection?.declaredChecksum
        )
        #expect(
            declared.declaredDigest
                == "36e78c5049560eaa8e122224f6652eb4b229c61cd5e7332d6d25b5c36f7398e7"
        )

        let noCheck = try #require(
            try Self.cask("no-check", from: ["cask-no-check"]).caskInspection?.declaredChecksum
        )
        // Declaring no checksum, distinguishably from declaring one — and the
        // literal never leaks out as though it were a digest.
        #expect(noCheck == .notChecked)
        #expect(noCheck.declaredDigest == nil)
        #expect(declared != noCheck)
    }

    @Test("An uninstalled package's detail carries no integrity value, structurally")
    func noPostInstallVerdictReachesAnUninstalledPackage() throws {
        // Nothing in this test installs anything: every record here is a catalog
        // record for a package that is not on the machine.
        let iterm = try Self.cask("iterm2", from: ["cask-iterm2"])
        let strings = ExposedFields.strings(of: iterm)

        #expect(strings.contains("iTerm.app"), "the walk did not reach the projected artifacts")
        for forbidden in Self.verdictVocabulary {
            #expect(
                strings.contains { $0.lowercased().contains(forbidden.lowercased()) } == false,
                "a detail value mentions \(forbidden)"
            )
        }

        // ...and the projection declares no dependency on the capability that
        // produces post-install verdicts. It cannot forward what it cannot see.
        for name in try CatalogSources.swiftFileNames() {
            let code = try CatalogSources.code(of: name)
            #expect(code.contains("import SecurityKit") == false, "\(name) imports SecurityKit")
            #expect(code.contains("import BrewProcess") == false, "\(name) imports BrewProcess")
        }
        CatalogSources.assertAnchored(
            try CatalogSources.code(of: "CatalogInspection.swift"), expecting: "CaskInspection"
        )
    }

    @Test("Nothing the projection exposes is runnable")
    func nothingExposedIsRunnable() throws {
        let plan = try #require(
            try Self.cask("every-stanza", from: ["cask-every-stanza"]).caskInspection?.installPlan
        )

        // The only artifact values exposed are the projected stanzas' sources
        // and destinations, plus the remainder count.
        let exposed = ExposedFields.strings(of: plan)
        #expect(
            Set(exposed) == [
                "Every Stanza.app",
                "/Applications/Every Stanza.app",
                "Every Stanza.app/Contents/MacOS/every-stanza",
                "every-stanza",
                "EveryStanza.pkg"
            ]
        )
        #expect(plan.unrepresentedStanzaCount == 2)

        // Not one directive, path or command from the `zap` or `uninstall`
        // stanzas the fixture publishes reached the projection.
        let dropped = [
            "launchctl", "pkgutil", "quit", "script", "trash", "rmdir", "sudo",
            "/usr/local/bin/every-stanza-uninstall",
            "~/Library/Application Support/EveryStanza",
            "~/Library/Preferences/invalid.example.every-stanza.plist",
            "~/Library/EveryStanza",
            "invalid.example.every-stanza"
        ]
        for directive in dropped {
            #expect(
                exposed.contains { $0.contains(directive) } == false,
                "the projection carried \(directive) out of a zap or uninstall stanza"
            )
        }

        // The whole record, not just the plan — nothing smuggled it in elsewhere.
        let everything = ExposedFields.strings(
            of: try Self.cask("every-stanza", from: ["cask-every-stanza"])
        )
        for directive in dropped {
            #expect(everything.contains { $0.contains(directive) } == false)
        }

        // And the projection offers no operation that would run any of it: the
        // whole target is free of the process and mutation vocabulary.
        for name in try CatalogSources.swiftFileNames() {
            let code = try CatalogSources.code(of: name)
            for forbidden in ["Process(", "MutationCommand", "OperationCenter", "launchctl"] {
                #expect(code.contains(forbidden) == false, "\(name) references \(forbidden)")
            }
        }
    }

    @Test("Formula source URLs are exposed, and an absent head URL stays absent")
    func formulaSourceURLsAreExposed() throws {
        let index = try Self.inspectionIndex(
            casks: ["cask-iterm2"],
            formulae: ["formula-git", "formula-headless"]
        )

        let git = try #require(index.package(PackageID(kind: .formula, name: "git")))
        #expect(
            git.formulaSources?.stableURL
                == "https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.55.0.tar.xz"
        )
        #expect(git.formulaSources?.headURL == "https://github.com/git/git.git")

        let headless = try #require(index.package(PackageID(kind: .formula, name: "headless")))
        #expect(
            headless.formulaSources?.stableURL
                == "https://example.invalid/releases/headless-3.1.4.tar.gz"
        )
        #expect(headless.formulaSources?.headURL == nil)

        // A formula never carries cask inspection, and a cask never carries
        // formula sources: the two groups are exclusive by construction.
        #expect(git.caskInspection == nil)
        #expect(
            try #require(index.package(PackageID(kind: .cask, name: "iterm2"))).formulaSources == nil
        )
    }
}
