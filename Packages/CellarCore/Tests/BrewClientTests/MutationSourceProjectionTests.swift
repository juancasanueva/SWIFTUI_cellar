import BrewProcess
import Catalog
import Foundation
import Testing

@testable import BrewClient

/// The `source` projection every spine command carries, and the erasure that
/// must not lose it (`package-mutation` — "Every spine command projects its
/// source, and the erased form preserves it"; `operation-activity` — "Activity
/// items carry their source"; design D12).
@MainActor
@Suite("Mutation source projection")
struct MutationSourceProjectionTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let iterm = PackageID(kind: .cask, name: "iterm2")
    private static let typescript = PackageID(kind: .npm, name: "typescript")

    private static func npmUpgrade() throws -> NpmCommand {
        .upgrade(try #require(NpmPackageTarget(typescript)))
    }

    private static func npmUninstall() throws -> NpmCommand {
        .uninstall(try #require(NpmPackageTarget(typescript)))
    }

    // MARK: - One package, one service, one tap and one npm command

    @Test("Existing families default to Homebrew and npm declares npm")
    func existingFamiliesDefaultToHomebrew() throws {
        let package = try #require(MutationCommand.upgrade(formula: "wget"))
        let service = try #require(ServiceCommand.start(service: "atuin"))
        let tap = try #require(TapCommand.add("acme/tools"))
        let cleanup = CleanupCommand(scope: .global)
        let npm = try Self.npmUpgrade()

        for command in [package.source, service.source, tap.source, cleanup.source] {
            #expect(command == .homebrew)
        }
        #expect(npm.source == .npm)

        #expect(package.displayCommand == "brew upgrade --formula wget")
        #expect(service.displayCommand.hasPrefix("brew "))
        #expect(tap.displayCommand.hasPrefix("brew "))
        #expect(cleanup.displayCommand.hasPrefix("brew "))
        #expect(npm.displayCommand == "npm install -g typescript@latest")
    }

    /// The erased form is where the projection has to survive: the activity
    /// list, the confirmation sheet and the terminal funnel all read
    /// `AnyBrewMutation` and never the concrete command.
    @Test("The erased form equals the unerased one in source and display command")
    func erasureCopiesTheSource() throws {
        let cases: [any BrewMutating] = [
            try #require(MutationCommand.upgrade(formula: "wget")),
            MutationCommand.upgradeAll,
            try #require(ServiceCommand.stop(service: "atuin")),
            try #require(TapCommand.untap("acme/tools")),
            try Self.npmUpgrade(),
            try Self.npmUninstall(),
        ]

        #expect(cases.count == 6)
        for command in cases {
            let erased = AnyBrewMutation(command)
            #expect(erased.source == command.source)
            #expect(erased.displayCommand == command.displayCommand)
        }
    }

    /// `operation-activity`: "An erased npm item never renders as brew."
    @Test("An erased npm command never renders or copies as a brew command")
    func erasedNpmNeverRendersAsBrew() throws {
        let erased = AnyBrewMutation(try Self.npmUninstall())

        #expect(erased.displayCommand == "npm uninstall -g typescript")
        #expect(erased.displayCommand.hasPrefix("npm "))
        #expect(erased.displayCommand.hasPrefix("brew ") == false)
        #expect(erased.arguments == ["uninstall", "-g", "typescript"])
    }

    /// Equality widens deliberately, exactly as it did when `disclosure` was
    /// added: two commands identical in argv but differing in source are not the
    /// same erased value, and they hash apart.
    @Test("Erased equality separates two sources that share an argv")
    func erasedEqualitySeparatesSources() throws {
        let npm = AnyBrewMutation(try Self.npmUninstall())
        let sameArgvUnderBrew = AnyBrewMutation(
            ProbeMutation(
                arguments: ["uninstall", "-g", "typescript"],
                verb: "npmUninstall",
                packageID: Self.typescript
            )
        )

        #expect(npm.arguments == sameArgvUnderBrew.arguments)
        #expect(npm != sameArgvUnderBrew)
        #expect(npm.hashValue != sameArgvUnderBrew.hashValue)
    }

    // MARK: - What the surfaces read

    @Test("An npm activity item carries npm's source in every state")
    func activityItemCarriesItsSource() async throws {
        let harness = CenterHarness(attached: true)
        harness.center.attach(npm: NpmEnvironmentFixture.detected)

        let item = harness.center.submit(try Self.npmUpgrade())

        #expect(item.source == .npm)
        #expect(item.displayCommand == "npm install -g typescript@latest")
        #expect(item.copyText == "npm install -g typescript@latest")

        try await harness.finish(call: 0, status: 0)

        #expect(item.isTerminal)
        #expect(item.source == .npm)
        #expect(item.copyText == "npm install -g typescript@latest")
    }

    @Test("A brew activity item is unchanged")
    func brewActivityItemIsUnchanged() async throws {
        let harness = CenterHarness(attached: true)
        let command = try #require(MutationCommand.install(cask: "iterm2"))

        let item = harness.center.submit(command)

        #expect(item.source == .homebrew)
        #expect(item.copyText == "brew install --cask iterm2")
    }

    /// The uninstall confirmation presents the exact text that will run — which
    /// for npm is an `npm` command, not a brew one (`npm-source`).
    @Test("An npm uninstall confirmation presents the exact npm command")
    func npmUninstallConfirmationPresentsTheNpmCommand() throws {
        let harness = CenterHarness(attached: true)
        harness.center.attach(npm: NpmEnvironmentFixture.detected)

        let request = try #require(harness.center.request([try Self.npmUninstall()]))

        #expect(request.command.displayCommand == "npm uninstall -g typescript")
        #expect(request.disclosure == .packageRemoval)
        #expect(harness.launcher.launchCount == 0)
    }

    // MARK: - Outcome copy

    @Test("Outcome messages name the source that actually ran")
    func outcomeMessagesNameTheirSource() throws {
        let brew = try #require(MutationCommand.upgrade(formula: "wget"))
        let npm = try Self.npmUpgrade()

        #expect(
            MutationOutcome.failed(status: 1).message(for: brew)
                == "Homebrew exited with status 1. The full output is below."
        )
        #expect(
            MutationOutcome.failed(status: 1).message(for: npm)
                == "npm exited with status 1. The full output is below."
        )

        for outcome in [MutationOutcome.failed(status: 2), .cancelled, .launchFailed] {
            #expect(outcome.message(for: npm).contains("Homebrew") == false)
            #expect(outcome.message(for: brew).contains("Homebrew"))
        }
    }

    /// The idle projection names no source at all: with nothing running there is
    /// no command to describe, so there is nothing for a one-source sentence to
    /// creep into.
    @Test("The idle summary names no source")
    func idleSummaryNamesNoSource() {
        let harness = CenterHarness(attached: true)

        let summary = harness.center.summary
        #expect(summary.isBusy == false)
        #expect(summary.running == nil)
        #expect(summary.runningCommand == nil)
        #expect(summary.pendingCount == 0)
    }

    /// And a queued npm item's in-flight copy is source-neutral rather than
    /// brew's, so a pending npm operation never reads as a Homebrew one.
    @Test("A queued npm item's in-flight copy names no other source")
    func queuedNpmCopyIsNotBrewOnly() throws {
        let harness = CenterHarness(attached: true)
        harness.center.attach(npm: NpmEnvironmentFixture.detected)

        let item = harness.center.submit(try Self.npmUpgrade())

        #expect(item.isTerminal == false)
        #expect(item.message.contains("Homebrew") == false)
        #expect(item.statusLabel == "Queued" || item.statusLabel == "Running")
    }
}
