import BrewProcess
import Catalog
import Foundation
import Testing

@testable import BrewClient

/// Source-keyed runners: which executable a submission reaches, and what
/// happens when the one it needs is not attached (`package-mutation` PM7 as
/// modified — availability is evaluated per source; `npm-source` — no npm
/// mutation is built or spawned while npm is disabled, absent or invalid;
/// design D13).
@MainActor
@Suite("Operation centre source routing")
struct OperationCenterSourceRoutingTests {
    private static let typescript = PackageID(kind: .npm, name: "typescript")

    private static func npmUpgrade() throws -> NpmCommand {
        .upgrade(try #require(NpmPackageTarget(typescript)))
    }

    // MARK: - Routing

    @Test("An npm submission spawns npm and a brew submission spawns brew")
    func submissionsReachTheirOwnExecutable() async throws {
        let harness = CenterHarness(attached: true)
        harness.center.attach(npm: NpmEnvironmentFixture.detected)

        harness.center.submit(try Self.npmUpgrade())
        try await harness.finish(call: 0, status: 0)
        harness.center.submit(try #require(MutationCommand.upgrade(formula: "wget")))
        try await harness.finish(call: 1, status: 0)

        let specs = harness.launcher.recordedSpecs
        #expect(specs.count == 2)
        #expect(specs[0].executableURL == NpmEnvironmentFixture.detected.executableURL)
        #expect(specs[0].arguments == ["install", "-g", "typescript@latest"])
        #expect(specs[1].executableURL == TestInstallation.appleSilicon.executableURL)
        #expect(specs[1].arguments == ["upgrade", "--formula", "wget"])
    }

    /// The npm runner composes npm's environment, so a brew pin can never reach
    /// an npm subprocess and vice versa.
    @Test("The npm runner spawns under npm's environment and no HOMEBREW key")
    func npmRunnerUsesTheNpmEnvironment() async throws {
        let harness = CenterHarness(attached: true)
        harness.center.attach(npm: NpmEnvironmentFixture.volta)

        harness.center.submit(try Self.npmUpgrade())
        try await harness.finish(call: 0, status: 0)

        let spec = try #require(harness.launcher.recordedSpecs.first)
        #expect(spec.environment["npm_config_progress"] == "false")
        #expect(spec.environment["PATH"]?.hasPrefix("/Users/tester/.volta/bin:") == true)
        #expect(spec.environment.keys.contains { $0.hasPrefix("HOMEBREW_") } == false)
    }

    // MARK: - A source with no attached runner

    /// `package-mutation`: "A source with no attached runner settles as a launch
    /// failure … spawns nothing, and records exactly one history entry."
    @Test("An npm submission with no npm runner settles as one launch failure")
    func missingNpmRunnerSettlesAsLaunchFailure() async throws {
        let harness = CenterHarness(attached: true)

        let item = harness.center.submit(try Self.npmUpgrade())
        await harness.settle()

        #expect(item.outcome == .launchFailed)
        #expect(harness.launcher.launchCount == 0)
        #expect(harness.recorder.drafts.count == 1)
        #expect(harness.recorder.drafts.first?.verb == "npmUpgrade")
        #expect(harness.recorder.drafts.first?.outcome == .launchFailed)
    }

    /// And the mirror image: a brew submission with brew detached is unchanged,
    /// so attaching npm cannot have made brew's own failure path source-blind.
    @Test("A brew submission with no brew runner still settles as one launch failure")
    func missingBrewRunnerIsUnchanged() async throws {
        let harness = CenterHarness(attached: false)
        harness.center.attach(npm: NpmEnvironmentFixture.detected)

        let item = harness.center.submit(try #require(MutationCommand.upgrade(formula: "wget")))
        await harness.settle()

        #expect(item.outcome == .launchFailed)
        #expect(harness.launcher.launchCount == 0)
        #expect(harness.recorder.drafts.count == 1)
    }

    // MARK: - Availability, per source

    @Test("Availability and guidance are evaluated per source")
    func availabilityIsPerSource() {
        let brewOnly = CenterHarness(attached: true)

        #expect(brewOnly.center.isAvailable(for: .homebrew))
        #expect(brewOnly.center.isAvailable(for: .npm) == false)
        #expect(brewOnly.center.unavailableGuidance(for: .homebrew) == nil)
        let npmGuidance = brewOnly.center.unavailableGuidance(for: .npm)
        #expect(npmGuidance?.contains("npm") == true)
        #expect(npmGuidance?.contains("Homebrew") == false)

        let npmOnly = CenterHarness(attached: false)
        npmOnly.center.attach(npm: NpmEnvironmentFixture.detected)

        #expect(npmOnly.center.isAvailable(for: .npm))
        #expect(npmOnly.center.isAvailable(for: .homebrew) == false)
        #expect(npmOnly.center.unavailableGuidance(for: .npm) == nil)
        #expect(npmOnly.center.unavailableGuidance(for: .homebrew)?.contains("Homebrew") == true)
    }

    /// The shipped, source-free `isAvailable` keeps answering for Homebrew, so
    /// every existing call site reads exactly what it read before.
    @Test("The shipped availability property still answers for Homebrew alone")
    func shippedAvailabilityStillMeansBrew() {
        let harness = CenterHarness(attached: true)
        harness.center.attach(npm: nil)

        #expect(harness.center.isAvailable)
        #expect(harness.center.unavailableGuidance == nil)

        let detached = CenterHarness(attached: false)
        detached.center.attach(npm: NpmEnvironmentFixture.detected)

        #expect(detached.center.isAvailable == false)
        #expect(detached.center.unavailableGuidance?.contains("Homebrew") == true)
    }

    // MARK: - Detaching and repointing

    @Test("Detaching npm removes only npm's runner")
    func detachingNpmLeavesBrewAttached() async throws {
        let harness = CenterHarness(attached: true)
        harness.center.attach(npm: NpmEnvironmentFixture.detected)
        #expect(harness.center.isAvailable(for: .npm))

        harness.center.attach(npm: nil)

        #expect(harness.center.isAvailable(for: .npm) == false)
        #expect(harness.center.isAvailable(for: .homebrew))

        let item = harness.center.submit(try Self.npmUpgrade())
        await harness.settle()
        #expect(item.outcome == .launchFailed)
        #expect(harness.launcher.launchCount == 0)
    }

    /// Becoming available needs no relaunch: the same centre answers differently
    /// the moment detection resolves.
    @Test("npm mutations become available the moment npm is attached")
    func npmBecomesAvailableWithoutRelaunch() async throws {
        let harness = CenterHarness(attached: true)
        #expect(harness.center.isAvailable(for: .npm) == false)

        harness.center.attach(npm: NpmEnvironmentFixture.detected)
        let item = harness.center.submit(try Self.npmUpgrade())
        try await harness.finish(call: 0, status: 0)

        #expect(item.outcome == .succeeded)
        #expect(harness.launcher.launchCount == 1)
    }
}
