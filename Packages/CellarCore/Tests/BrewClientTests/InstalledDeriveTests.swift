import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// Every badge the Installed list shows is derived from the one payload
/// (installed-inventory II3–II6). No rule here may cost a second `brew`
/// invocation.
@Suite("Installed state derivation")
struct InstalledDeriveTests {
    @Test("Absent linked keg stays unlinked while an older linked keg remains exact")
    func linkedKegStateIsNotInferredFromPrimaryKeg() throws {
        let payload = Data(#"""
        {"formulae":[
          {"name":"unlinked","installed":[
            {"version":"1.0","time":100,"installed_on_request":true},
            {"version":"2.0","time":200,"installed_on_request":true}]},
          {"name":"older-linked","linked_keg":"1.0","installed":[
            {"version":"1.0","time":100,"installed_on_request":true},
            {"version":"2.0","time":200,"installed_on_request":true}]}
        ],"casks":[]}
        """#.utf8)

        let inventory = try InstalledDecoder.inventory(from: payload)
        let unlinked = try #require(inventory.packages.first { $0.name == "unlinked" })
        let linked = try #require(inventory.packages.first { $0.name == "older-linked" })

        #expect(unlinked.linkedKeg == nil)
        #expect(unlinked.primaryKeg.version == "2.0")
        #expect(linked.linkedKeg == "1.0")
        #expect(linked.formulaLinkState == .linked("1.0"))
    }
    // MARK: - Outdated (II4)

    @Test("An outdated formula is in the outdated set and counted")
    func outdatedFormulaIsReportedAndCounted() throws {
        let inventory = try InstalledFixture.inventory()
        let git = try #require(inventory.package(PackageID(kind: .formula, name: "git")))

        #expect(git.isOutdated)
        #expect(inventory.outdatedIDs.contains(git.id))
        #expect(inventory.outdatedCount >= 1)
    }

    @Test("A cask that does not declare auto-updates is outdated on the same terms")
    func caskWithoutAutoUpdatesIsOutdatedLikeAFormula() throws {
        let inventory = try InstalledFixture.inventory()
        let transmission = try #require(
            inventory.package(PackageID(kind: .cask, name: "transmission"))
        )

        #expect(transmission.declaresAutoUpdates == nil)
        #expect(transmission.isSelfUpdating == false)
        #expect(transmission.isOutdated)
        #expect(inventory.outdatedIDs.contains(transmission.id))
    }

    @Test("A self-updating cask behind its published version is never outdated")
    func selfUpdatingCaskIsNeverOutdated() throws {
        let inventory = try InstalledFixture.inventory()
        let ghostty = try #require(inventory.package(PackageID(kind: .cask, name: "ghostty")))

        // Genuinely behind: installed 1.2.3, published 1.3.1.
        #expect(ghostty.installedVersion == "1.2.3")
        #expect(ghostty.catalogVersion == "1.3.1")

        #expect(ghostty.isSelfUpdating)
        #expect(ghostty.isOutdated == false)
        #expect(inventory.outdatedIDs.contains(ghostty.id) == false)
    }

    @Test("The outdated count counts the outdated set and nothing else")
    func outdatedCountMatchesTheOutdatedSet() throws {
        let inventory = try InstalledFixture.inventory()

        #expect(inventory.outdatedCount == inventory.outdatedIDs.count)
        // Exactly the outdated formula and the cask that declares nothing —
        // the two self-updating casks are excluded even though one is behind.
        #expect(
            inventory.outdatedIDs.map(\.name).sorted() == ["git", "transmission"]
        )
    }

    /// Belt-and-braces (design D4): brew's own snapshot already applies the
    /// auto-updates exclusion, so this shape should never arrive. If a future
    /// brew starts emitting it, Cellar still must not nag.
    @Test("A self-updating cask stays out of the set even if the snapshot says outdated")
    func selfUpdatingCaskIsExcludedEvenWhenTheSnapshotSaysOutdated() {
        let cask = InstalledDeriveTests.cask(
            name: "impossible",
            installed: "1.0.0",
            published: "2.0.0",
            snapshotOutdated: true,
            declaresAutoUpdates: true
        )
        let inventory = InstalledInventory(packages: [cask])

        #expect(cask.snapshotOutdated)
        #expect(cask.isOutdated == false)
        #expect(inventory.outdatedIDs.isEmpty)
        #expect(inventory.outdatedCount == 0)
    }

    // MARK: - The newer-version signal (II5)

    @Test("The newer-version signal comes from the same single invocation")
    func newerVersionIsDerivedWithoutASecondInvocation() async throws {
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: String(decoding: try InstalledFixture.data(), as: UTF8.self))
        ])
        let source = BrewInfoPayloadSource(launcher: launcher)

        let payload = try await source.payload(using: TestInstallation.appleSilicon)
        let inventory = try await InstalledDecoder.decode(payload)
        let ghostty = try #require(inventory.package(PackageID(kind: .cask, name: "ghostty")))

        #expect(ghostty.hasNewerVersion)
        #expect(launcher.launchCount == 1)
    }

    @Test("Matching versions produce no signal, and still no outdated membership")
    func matchingVersionsProduceNoSignal() throws {
        let inventory = try InstalledFixture.inventory()
        let firefox = try #require(inventory.package(PackageID(kind: .cask, name: "firefox")))

        #expect(firefox.isSelfUpdating)
        #expect(firefox.installedVersion == firefox.catalogVersion)
        #expect(firefox.hasNewerVersion == false)
        #expect(inventory.outdatedIDs.contains(firefox.id) == false)
    }

    /// The signal is informational. It must never reach the set, the count, or a
    /// badge — which is exactly what makes it safe to show separately.
    @Test("The newer-version signal never reaches the outdated set or count")
    func newerVersionNeverFeedsTheOutdatedSet() throws {
        let inventory = try InstalledFixture.inventory()
        let signalled = inventory.packages.filter(\.hasNewerVersion)

        #expect(signalled.map(\.name) == ["ghostty"])
        #expect(signalled.allSatisfy { inventory.outdatedIDs.contains($0.id) == false })
        #expect(inventory.outdatedCount == 2)
    }

    @Test("A formula behind its published version raises no self-updating signal")
    func formulaeNeverRaiseTheSignal() throws {
        let inventory = try InstalledFixture.inventory()
        let git = try #require(inventory.package(PackageID(kind: .formula, name: "git")))

        // git is genuinely behind — that is what `isOutdated` is for.
        #expect(git.installedVersion != git.catalogVersion)
        #expect(git.hasNewerVersion == false)
    }

    // MARK: - On request and dependency-only (II3)

    @Test("The default view hides dependency-only formulae")
    func defaultViewHidesDependencyOnlyFormulae() throws {
        let inventory = try InstalledFixture.inventory()

        let listed = inventory.packages(includingDependencies: false).map(\.name)

        #expect(listed.contains("wget"))
        #expect(listed.contains("libunistring") == false)
    }

    @Test("The dependency toggle reveals them, and each says which it was")
    func toggleRevealsDependencyOnlyFormulae() throws {
        let inventory = try InstalledFixture.inventory()

        let listed = inventory.packages(includingDependencies: true)
        let names = listed.map(\.name)

        #expect(names.contains("wget"))
        #expect(names.contains("libunistring"))
        let wget = try #require(listed.first { $0.name == "wget" })
        let libunistring = try #require(listed.first { $0.name == "libunistring" })
        #expect(wget.isOnRequest)
        #expect(libunistring.isOnRequest == false)
    }

    /// A formula with several kegs counts as on request when *any* keg was.
    /// Pulled in as a dependency first, then asked for by name, is still asked
    /// for by name.
    @Test("A formula asked for on any keg is on request")
    func anyOnRequestKegMakesTheFormulaOnRequest() throws {
        let openssl = try InstalledFixture.package(.formula, "openssl@3")

        #expect(openssl.kegs.contains { !$0.installedOnRequest })
        #expect(openssl.isOnRequest)
    }

    @Test("A cask, whose records carry no on-request marker, is listed by default")
    func casksAreAlwaysOnRequest() throws {
        let inventory = try InstalledFixture.inventory()

        let listed = inventory.packages(includingDependencies: false)
        let ghostty = try #require(listed.first { $0.id.kind == .cask && $0.name == "ghostty" })

        #expect(ghostty.isOnRequest)
        // Nothing a user deliberately installed may be hidden by the default
        // view, and every cask is deliberate.
        #expect(listed.count { $0.kind == .cask } == 4)
    }

    // MARK: - Pin state and install date (II6)

    @Test("Pin state is exposed for both kinds, with the recorded pinned version")
    func pinStateIsExposedForBothKinds() throws {
        let python = try InstalledFixture.package(.formula, "python@3.12")
        let docker = try InstalledFixture.package(.cask, "docker-desktop")

        #expect(python.isPinned)
        #expect(python.pinnedVersion == "3.12.7")
        #expect(docker.isPinned)
        #expect(docker.pinnedVersion == "4.38.0")
    }

    @Test("An unpinned package reports no pin and no pinned version")
    func unpinnedPackagesReportNothing() throws {
        let wget = try InstalledFixture.package(.formula, "wget")
        let ghostty = try InstalledFixture.package(.cask, "ghostty")

        #expect(wget.isPinned == false)
        #expect(wget.pinnedVersion == nil)
        #expect(ghostty.isPinned == false)
        #expect(ghostty.pinnedVersion == nil)
    }

    @Test("Install dates are the recorded timestamps read as epoch seconds")
    func installDatesComeFromTheRecordedTimestamps() throws {
        let wget = try InstalledFixture.package(.formula, "wget")
        let transmission = try InstalledFixture.package(.cask, "transmission")

        #expect(wget.installedAt == InstalledFixture.date(1_735_689_600))
        #expect(transmission.installedAt == InstalledFixture.date(1_730_419_200))
    }

    /// Both pin state and install dates come out of the same snapshot, so
    /// `brew list --pinned` is never spawned for them.
    @Test("Pin state and install dates cost no extra invocation")
    func pinAndDateCostNoExtraInvocation() async throws {
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: String(decoding: try InstalledFixture.data(), as: UTF8.self))
        ])
        let source = BrewInfoPayloadSource(launcher: launcher)

        let inventory = try await InstalledDecoder.decode(
            try await source.payload(using: TestInstallation.appleSilicon)
        )
        let pinned = inventory.packages.filter(\.isPinned)

        #expect(pinned.map(\.name).sorted() == ["docker-desktop", "python@3.12"])
        #expect(inventory.packages.allSatisfy { $0.installedAt.timeIntervalSince1970 > 0 })
        #expect(launcher.launchCount == 1)
        #expect(launcher.specs.allSatisfy { !$0.arguments.contains("--pinned") })
    }

    // MARK: - Builders

    static func cask(
        name: String,
        installed: String,
        published: String,
        snapshotOutdated: Bool,
        declaresAutoUpdates: Bool?,
        isPinned: Bool = false,
        pinnedVersion: String? = nil
    ) -> InstalledPackage {
        let keg = InstalledKeg(
            version: installed,
            installedAt: InstalledFixture.date(1_700_000_000),
            installedOnRequest: true
        )
        return InstalledPackage(
            kind: .cask,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            tap: "homebrew/cask",
            catalogVersion: published,
            kegs: [keg],
            primaryKeg: keg,
            snapshotOutdated: snapshotOutdated,
            isPinned: isPinned,
            pinnedVersion: pinnedVersion,
            declaresAutoUpdates: declaresAutoUpdates
        )
    }

    static func formula(
        name: String,
        installed: String,
        published: String? = nil,
        snapshotOutdated: Bool = false,
        onRequest: Bool = true,
        isPinned: Bool = false,
        pinnedVersion: String? = nil
    ) -> InstalledPackage {
        let keg = InstalledKeg(
            version: installed,
            installedAt: InstalledFixture.date(1_700_000_000),
            installedOnRequest: onRequest
        )
        return InstalledPackage(
            kind: .formula,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            tap: "homebrew/core",
            catalogVersion: published ?? installed,
            kegs: [keg],
            primaryKeg: keg,
            snapshotOutdated: snapshotOutdated,
            isPinned: isPinned,
            pinnedVersion: pinnedVersion,
            declaresAutoUpdates: nil
        )
    }

    // MARK: - II2 :116 — every reader of an installed tap treats absence as no match

    /// **DD-11.** This migration is *not* compiler-enforced. Swift promotes the
    /// non-optional operand of `==`, so all three shipped readers keep compiling
    /// and stay semantically correct — which means nothing but this test pins
    /// them. Each predicate below is the exact expression its reader evaluates.
    @Test("Every reader of an installed tap treats absence as no match")
    func everyTapReaderTreatsAbsenceAsNoMatch() throws {
        let payload = Data(#"""
        {"formulae":[
          {"name":"widget","tap":null,"versions":{"stable":"2.0"},"installed":[
            {"version":"2.0","time":100,"installed_on_request":true}]},
          {"name":"named","tap":"acme/tools","versions":{"stable":"1.0"},"installed":[
            {"version":"1.0","time":100,"installed_on_request":true}]},
          {"name":"core","tap":"homebrew/core","versions":{"stable":"1.0"},"installed":[
            {"version":"1.0","time":100,"installed_on_request":true}]}
        ],"casks":[]}
        """#.utf8)

        let inventory = try InstalledDecoder.inventory(from: payload)
        let withheld = try #require(inventory.package(PackageID(kind: .formula, name: "widget")))
        let named = try #require(inventory.package(PackageID(kind: .formula, name: "named")))
        let core = try #require(inventory.package(PackageID(kind: .formula, name: "core")))

        // Absence matches neither a tap name nor the sentinel it used to become.
        #expect(withheld.tap == nil)
        #expect((withheld.tap == "acme/tools") == false)
        #expect((withheld.tap == "") == false)

        // Reader 1 — `TapProjection`'s exact-tap cross-reference (:146).
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget", "acme/tools/named"]
        )
        let projected = TapProjection.packages(for: tap, installed: inventory)
        let widgetRow = try #require(projected.first { $0.displayName == "widget" })
        let namedRow = try #require(projected.first { $0.displayName == "named" })
        #expect(widgetRow.installedHandoff == nil, "a withheld tap matched the selected tap exactly")
        #expect(namedRow.installedHandoff == PackageID(kind: .formula, name: "named"))

        // Reader 2 — `ContentView.forceEvidence`'s affected-set filter, the same
        // predicate it applies. A withheld record is excluded, so force untap
        // stays hidden while a tap is untrusted (DD-14, fail-closed).
        let affected = Set(inventory.packages.lazy.filter { $0.tap == "acme/tools" }.map(\.id))
        #expect(affected == [PackageID(kind: .formula, name: "named")])

        // Reader 3 — `HomebrewUpdateNeed.isComparable`, the same predicate.
        #expect((withheld.tap == "homebrew/core") == false)
        #expect((withheld.tap == "homebrew/cask") == false)
        #expect(core.tap == "homebrew/core")
        #expect(named.tap == "acme/tools")

        // And the sentinel may not come back in either app-target reader, which
        // is the one way this migration could be silently undone.
        for source in try Self.appTapReaderSources() {
            #expect(
                source.code.contains("tap ?? \"\"") == false,
                "\(source.name) reintroduced the empty-string tap sentinel"
            )
        }
    }

    private struct AppSource {
        let name: String
        let code: String
    }

    private static func appTapReaderSources() throws -> [AppSource] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try ["cellar/ContentView.swift", "cellar/Home/HomebrewUpdateNeed.swift"].map { path in
            AppSource(
                name: path,
                code: try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            )
        }
    }
}
