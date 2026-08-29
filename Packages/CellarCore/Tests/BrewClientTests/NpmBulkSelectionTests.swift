import CellarTestSupport
import Catalog
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// What a selection expands to when it holds more than one source
/// (`package-mutation` — "A brew argv can never name an npm package"; the
/// maintainer decision that npm updates apply per package, with select-all in
/// the Updates lens).
@MainActor
@Suite("npm bulk selection", .timeLimit(.minutes(1)))
struct NpmBulkSelectionTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let iterm = PackageID(kind: .cask, name: "iterm2")
    private static let typescript = PackageID(kind: .npm, name: "typescript")

    /// The spec's own selection, in the spec's own order.
    private static let mixed = [wget, typescript, iterm]

    private static func attached() -> CenterHarness {
        let harness = CenterHarness(attached: true)
        harness.center.attach(npm: NpmEnvironmentFixture.detected)
        return harness
    }

    // MARK: - Fan-out by source, in selection order

    @Test("A mixed bulk upgrade fans out by source in selection order")
    func mixedUpgradeFansOutBySource() {
        let harness = Self.attached()

        let commands = harness.center.commands(for: .upgrade, over: Self.mixed)

        #expect(commands.map(\.arguments) == [
            ["upgrade", "--formula", "wget"],
            ["install", "-g", "typescript@latest"],
            ["upgrade", "--cask", "iterm2"],
        ])
        #expect(commands.map(\.source) == [.homebrew, .npm, .homebrew])
        #expect(commands.map(\.displayCommand) == [
            "brew upgrade --formula wget",
            "npm install -g typescript@latest",
            "brew upgrade --cask iterm2",
        ])
    }

    /// Triangulation: uninstall is the other verb both sources own, and it must
    /// fan out the same way rather than dropping the npm member silently.
    @Test("A mixed bulk uninstall fans out by source in selection order")
    func mixedUninstallFansOutBySource() {
        let harness = Self.attached()

        let commands = harness.center.commands(for: .uninstall, over: Self.mixed)

        #expect(commands.map(\.arguments) == [
            ["uninstall", "--formula", "wget"],
            ["uninstall", "-g", "typescript"],
            ["uninstall", "--cask", "iterm2"],
        ])
        #expect(commands.map(\.verb) == ["uninstall", "npmUninstall", "uninstall"])
    }

    @Test("A mixed bulk upgrade enqueues exactly three operations through the one queue")
    func mixedUpgradeEnqueuesThroughOneQueue() async throws {
        let harness = Self.attached()

        harness.center.submitBulk(.upgrade, over: Self.mixed)
        await harness.settle()

        #expect(harness.center.items.count == 3)
        #expect(harness.center.items.map(\.source) == [.homebrew, .npm, .homebrew])

        for index in 0..<3 {
            await TestPoll.until(harness.launcher.launchCount >= index + 1)
            try await harness.finish(call: index, status: 0)
        }

        #expect(harness.launcher.recordedSpecs.map(\.executableURL) == [
            TestInstallation.appleSilicon.executableURL,
            NpmEnvironmentFixture.detected.executableURL,
            TestInstallation.appleSilicon.executableURL,
        ])
        #expect(harness.center.items.allSatisfy { $0.outcome == .succeeded })
    }

    /// And the per-package fan-out the Updates lens uses reaches the same three
    /// commands, so the two entry points cannot disagree about what a selection
    /// expands to.
    @Test("The upgrade fan-out reaches npm identities too")
    func upgradeFanOutReachesNpm() async throws {
        let harness = Self.attached()

        let items = harness.center.submitUpgrades(for: Self.mixed)

        #expect(items.count == 3)
        #expect(items.map(\.displayCommand) == [
            "brew upgrade --formula wget",
            "npm install -g typescript@latest",
            "brew upgrade --cask iterm2",
        ])

        for index in 0..<3 {
            await TestPoll.until(harness.launcher.launchCount >= index + 1)
            try await harness.finish(call: index, status: 0)
        }
    }

    // MARK: - The verbs npm is excluded from

    @Test("Pin, unpin and reinstall never see an npm identity")
    func pinUnpinAndReinstallExcludeNpm() {
        let harness = Self.attached()

        #expect(harness.center.commands(for: .pin, over: Self.mixed).map(\.arguments)
            == [["pin", "--formula", "wget"]])
        #expect(harness.center.commands(for: .unpin, over: Self.mixed).map(\.arguments)
            == [["unpin", "--formula", "wget"]])

        // Reinstall has no bulk form at all, and no npm command can be built for
        // it in any case: the brew factory refuses the identity.
        #expect(MutationCommand.naming(Self.typescript, MutationCommand.reinstall) == nil)
    }

    @Test("The eligible sets exclude npm from pin, unpin and the bulk upgrade")
    func eligibleSetsExcludeNpm() {
        let inventory = InstalledFixture.inventory(
            outdated: [Self.wget: "2.0.0", Self.typescript: "5.7.0"],
            upToDate: [Self.iterm]
        )
        let entries = InstalledBrowse(inventory: inventory, isAvailable: true)
            .entries(includingDependencies: true, catalogLookup: { _ in nil })
        let selection = BulkSelection(selection: Self.mixed, entries: entries)

        // Positively anchored: the npm row really is in the inventory and really
        // is outdated, so its absence below is an exclusion rather than a miss.
        #expect(inventory.package(Self.typescript)?.isOutdated == true)
        #expect(selection.uninstallable.contains(Self.typescript))

        #expect(selection.upgradable == [Self.wget])
        #expect(selection.pinnable.contains(Self.typescript) == false)
        #expect(selection.unpinnable.contains(Self.typescript) == false)
    }

    // MARK: - The grouped upgrade is untouched

    /// `package-mutation`: "The grouped `upgrade` (all) MUST remain a bare
    /// `brew upgrade` naming no npm package; npm updates apply per package only."
    @Test("Upgrade all stays a bare brew upgrade with no npm fan-out")
    func upgradeAllStaysBare() async throws {
        let harness = Self.attached()

        let item = harness.center.submit(MutationCommand.upgradeAll)
        await harness.settle()

        #expect(harness.center.items.count == 1, "the grouped upgrade fanned out")
        #expect(item.arguments == ["upgrade"])
        #expect(item.source == .homebrew)
        #expect(item.displayCommand == "brew upgrade")

        try await harness.finish(call: 0, status: 0)

        #expect(harness.launcher.recordedSpecs.map(\.executableURL)
            == [TestInstallation.appleSilicon.executableURL])
        #expect(harness.launcher.recordedSpecs.allSatisfy {
            $0.arguments.contains("typescript") == false && $0.arguments.contains("-g") == false
        })
    }
}
