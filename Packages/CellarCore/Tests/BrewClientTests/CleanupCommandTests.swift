import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

@Suite("Cleanup command boundary")
struct CleanupCommandTests {
    struct CommandCase: Sendable, CustomTestStringConvertible {
        let scope: CleanupScope
        let preview: [String]
        let mutation: [String]
        let overrides: Set<BrewEnvironment.CommandOverride>
        let verb: String

        var testDescription: String { mutation.joined(separator: " ") }
    }

    static let wget = PackageTarget(kind: .formula, name: "wget")!
    static let iterm = PackageTarget(kind: .cask, name: "iterm2")!

    static let cases: [CommandCase] = [
        CommandCase(
            scope: .global,
            preview: ["cleanup", "--dry-run"],
            mutation: ["cleanup"],
            overrides: [.noAutoremove],
            verb: "cleanupGlobal"
        ),
        CommandCase(
            scope: .package(wget),
            preview: ["cleanup", "--dry-run", "wget"],
            mutation: ["cleanup", "wget"],
            overrides: [.noAutoremove],
            verb: "cleanupPackage"
        ),
        CommandCase(
            scope: .package(iterm),
            preview: ["cleanup", "--dry-run", "iterm2"],
            mutation: ["cleanup", "iterm2"],
            overrides: [.noAutoremove],
            verb: "cleanupPackage"
        ),
        CommandCase(
            scope: .full,
            preview: ["cleanup", "--dry-run", "--prune=all"],
            mutation: ["cleanup", "--prune=all"],
            overrides: [.noAutoremove],
            verb: "cleanupFull"
        ),
        CommandCase(
            scope: .autoremove,
            preview: ["autoremove", "--dry-run"],
            mutation: ["autoremove"],
            overrides: [],
            verb: "cleanupAutoremove"
        ),
    ]

    @Test("Every cleanup scope has exact preview and mutation argv", arguments: cases)
    func exactScopeMatrix(testCase: CommandCase) {
        let command = CleanupCommand(scope: testCase.scope)

        #expect(command.previewCommand.arguments == testCase.preview)
        #expect(command.previewCommand.kind == .read)
        #expect(command.arguments == testCase.mutation)
        #expect(command.brewCommand.arguments == testCase.mutation)
        #expect(command.brewCommand.kind == .mutate)
        #expect(command.environmentOverrides == testCase.overrides)
        #expect(command.previewCommand.environmentOverrides == testCase.overrides)
        #expect(command.brewCommand.environmentOverrides == testCase.overrides)
        #expect(command.verb == testCase.verb)
    }

    @Test("Package cleanup retains the validated package kind and name")
    func packageScopeRetainsIdentity() {
        let formula = CleanupCommand(scope: .package(Self.wget))
        let cask = CleanupCommand(scope: .package(Self.iterm))

        #expect(formula.packageID == PackageID(kind: .formula, name: "wget"))
        #expect(cask.packageID == PackageID(kind: .cask, name: "iterm2"))
        #expect(formula.scope == .package(Self.wget))
        #expect(cask.scope == .package(Self.iterm))
    }

    @Test(
        "Hostile package targets are rejected with guidance before command construction",
        arguments: ["", " ", "bad name", "--force"]
    )
    func hostileTargetsAreRejected(name: String) {
        #expect(CleanupCommand.package(kind: .formula, name: name) == nil)

        switch CleanupCommand.validatingPackage(kind: .formula, name: name) {
        case .success(let command):
            Issue.record("hostile target produced argv: \(command.arguments)")
        case .failure(let rejection):
            #expect(rejection == .invalidPackageName)
            #expect(rejection.guidance.isEmpty == false)
        }
    }

    @Test("Rejected package targets reach neither queue nor process seam")
    func rejectedTargetsSpawnNothing() async {
        let launcher = RecordingProcessLauncher()
        let runner = BrewRunner(installation: TestInstallation.appleSilicon, launcher: launcher)

        for name in ["", "bad name", "--force"] {
            guard let command = CleanupCommand.package(kind: .formula, name: name) else { continue }
            _ = try? await runner.start(command.brewCommand)
        }

        #expect(launcher.launchCount == 0)
        #expect(launcher.specs.isEmpty)
    }

    @Test("Preview and mutation reach brew directly with exact argv and local overrides")
    func processSpecsStayTypedAndShellFree() async throws {
        let launcher = RecordingProcessLauncher([ScriptedRun(), ScriptedRun()])
        let runner = BrewRunner(installation: TestInstallation.appleSilicon, launcher: launcher)
        let command = CleanupCommand(scope: .full)

        let preview = try await runner.start(command.previewCommand)
        _ = await preview.exit()
        let mutation = try await runner.start(command.brewCommand)
        _ = await mutation.exit()

        #expect(launcher.specs.map(\.arguments) == [
            ["cleanup", "--dry-run", "--prune=all"],
            ["cleanup", "--prune=all"],
        ])
        #expect(launcher.specs.allSatisfy {
            $0.executableURL == TestInstallation.appleSilicon.executableURL
                && $0.executableURL.path.contains("sh") == false
                && $0.arguments.contains("-c") == false
                && $0.environment["HOMEBREW_NO_AUTOREMOVE"] == "1"
        })
    }
}
