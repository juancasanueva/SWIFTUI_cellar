import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// Every badge the Installed list shows is derived from the one payload
/// (installed-inventory II3–II6). No rule here may cost a second `brew`
/// invocation.
@Suite("Installed state derivation")
struct InstalledDeriveTests {
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
        onRequest: Bool = true
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
            isPinned: false,
            pinnedVersion: nil,
            declaresAutoUpdates: nil
        )
    }
}
