import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

@MainActor
@Suite("Tap shipping proofs", .timeLimit(.minutes(1)))
struct TapShippingProofTests {
    @Test(
        "Every unavailable detection state blocks all tap process paths",
        arguments: UnavailableTapScenario.all
    )
    func unavailableDetectionBlocksEveryTapProcessPath(
        scenario: UnavailableTapScenario
    ) async throws {
        let launcher = RecordingProcessLauncher()
        let store = TapStore(source: BrewTapPayloadSource(launcher: launcher))
        let coordinator = TapRefreshCoordinator(store: store)
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: scenario.detection.installation)

        await store.refresh(for: scenario.detection)
        let requestedData = store.inventory
        await coordinator.refresh(for: scenario.detection)

        let addCommand = try #require(TapCommand.add("acme/tools"))
        let addRequest = try #require(center.request(addCommand))
        let addItems = center.confirm(addRequest)
        let untapItem = center.submit(try #require(TapCommand.untap("acme/tools")))
        await settle(addItems + [untapItem])

        #expect(requestedData.taps.isEmpty)
        #expect(store.inventory.taps.isEmpty)
        #expect(store.absence == scenario.absence)
        #expect(
            TapProjection.state(loadState: store.state, inventory: store.inventory)
                == .unavailable(scenario.absence)
        )
        #expect(addItems.count == 1)
        #expect((addItems + [untapItem]).allSatisfy { $0.outcome == .launchFailed })
        #expect(launcher.launchCount == 0, "\(scenario) spawned a tap process")
    }

    @Test("Absent taps recover and mutate in the same process lifetime")
    func absentDetectionRecoversInPlace() async throws {
        let launcher = recoveryLauncher()
        let store = TapStore(source: BrewTapPayloadSource(launcher: launcher))
        let coordinator = TapRefreshCoordinator(store: store)
        let center = OperationCenter(launcherFactory: { _ in launcher })

        center.attach(installation: nil)
        await coordinator.refresh(for: .absent)
        #expect(store.state == .brewAbsent(.notInstalled(.standard)))
        #expect(center.isAvailable == false)
        #expect(launcher.launchCount == 0)

        let detected = BrewDetectionState.detected(TestInstallation.appleSilicon)
        center.attach(installation: detected.installation)
        await coordinator.refresh(for: detected)
        #expect(store.state == .loaded)
        #expect(store.inventory.taps.map(\.name) == ["acme/tools"])
        #expect(center.isAvailable)

        let addCommand = try #require(TapCommand.add("other/home"))
        let addRequest = try #require(center.request(addCommand))
        let addItems = center.confirm(addRequest)
        let untapItem = center.submit(try #require(TapCommand.untap("acme/tools")))
        await settle(addItems + [untapItem])

        #expect((addItems + [untapItem]).allSatisfy { $0.outcome == .succeeded })
        #expect(launcher.specs.map(\.arguments) == [
            ["tap-info", "--installed", "--json"],
            ["tap", "other/home"],
            ["untap", "acme/tools"]
        ])
    }

    @Test("The complete tap action surface stays bounded to its six capabilities")
    func completeActionSurfaceIsBounded() async throws {
        let launcher = actionSurfaceLauncher()
        let store = TapStore(source: BrewTapPayloadSource(launcher: launcher))
        let installed = try installedInventory()
        var commands: [TapCommand] = []

        #expect(TapManagementAction.allCases.map(\.rawValue) == [
            "refresh", "filter", "Installed handoff", "canonical add", "plain untap",
            "eligible force untap"
        ])
        for action in TapManagementAction.allCases {
            if let command = try await exercise(action, store: store, installed: installed) {
                commands.append(command)
            }
        }

        #expect(launcher.specs.map(\.arguments) == [["tap-info", "--installed", "--json"]])
        #expect(commands.map(\.arguments) == [
            ["tap", "other/home"],
            ["untap", "acme/tools"],
            ["untap", "--force", "acme/tools"]
        ])
        #expect(commands.map(\.invalidates) == [
            .taps,
            .taps,
            [.taps, .installedInventory, .diskUsage]
        ])
        #expect(commands.allSatisfy { $0.packageID == nil })
        try assertBoundedUIControls()
    }

    private func exercise(
        _ action: TapManagementAction,
        store: TapStore,
        installed: InstalledInventory
    ) async throws -> TapCommand? {
        switch action {
        case .refresh:
            await store.refresh(using: TestInstallation.appleSilicon)
            #expect(store.state == .loaded)
            return nil
        case .filter:
            let packages = try packages(store: store, installed: installed)
            #expect(
                TapProjection.filter(packages, query: "other", kind: .formula)
                    .map(\.displayName) == ["other"]
            )
            return nil
        case .installedHandoff:
            let packages = try packages(store: store, installed: installed)
            #expect(
                packages.first(where: { $0.displayName == "widget" })?.installedHandoff
                    == PackageID(kind: .formula, name: "widget")
            )
            return nil
        case .canonicalAdd:
            let target = ["other", "home"].joined(separator: "/")
            guard let command = TapCommand.add(target) else {
                Issue.record("canonical add was unavailable")
                return nil
            }
            return command
        case .plainUntap:
            let target = ["acme", "tools"].joined(separator: "/")
            guard let command = TapCommand.untap(target) else {
                Issue.record("plain untap was unavailable")
                return nil
            }
            return command
        case .eligibleForceUntap:
            let tap = try #require(TapName("acme/tools"))
            let affected = Set(
                try packages(store: store, installed: installed).compactMap(\.installedHandoff)
            )
            guard let command = TapCommand.forceUntap(evidence: ForceUntapEvidence(
                tap: tap,
                affected: affected,
                isComplete: true
            )) else {
                Issue.record("eligible force untap was unavailable")
                return nil
            }
            return command
        }
    }

    private func packages(
        store: TapStore,
        installed: InstalledInventory
    ) throws -> [TapPackage] {
        let tap = try #require(store.inventory.taps.first)
        return TapProjection.packages(for: tap, installed: installed)
    }

    private func assertBoundedUIControls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let tapUI = try ["TapsListView.swift", "TapDetailView.swift"]
            .map { file in
                try String(
                    contentsOf: root.appendingPathComponent("cellar/Taps/\(file)"),
                    encoding: .utf8
                )
            }
            .joined(separator: "\n")

        #expect(try staticButtonLabels(in: tapUI) == [
            "Add Tap", "Untap", "Force Untap", "Show in Installed"
        ])
        #expect(tapUI.contains("Button {") == false, "an unenumerated dynamic tap button exists")
    }

    private func staticButtonLabels(in source: String) throws -> Set<String> {
        let expression = try NSRegularExpression(pattern: #"Button\("([^"]+)""#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(expression.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        })
    }

    private func settle(_ items: [ActivityItem]) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !items.allSatisfy(\.isTerminal), ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    private func recoveryLauncher() -> RecordingProcessLauncher {
        RecordingProcessLauncher([
            ScriptedRun(stdout: "[{\"name\":\"acme/tools\",\"repo\":\"tools\"}]\n"),
            ScriptedRun(stdout: ""),
            ScriptedRun(stdout: "")
        ])
    }

    private func actionSurfaceLauncher() -> RecordingProcessLauncher {
        RecordingProcessLauncher([ScriptedRun(stdout: """
        [{"name":"acme/tools","repo":"tools",\
        "formula_names":["acme/tools/widget","acme/tools/other"],"cask_tokens":["desk"]}]
        """)])
    }

    private func installedInventory() throws -> InstalledInventory {
        try InstalledDecoder.inventory(from: Data("""
        {"formulae":[{"name":"widget","tap":"acme/tools","versions":{"stable":"1.0"},\
        "installed":[{"version":"1.0","time":0,"installed_on_request":true}]}],"casks":[]}
        """.utf8))
    }
}

struct UnavailableTapScenario: Sendable, CustomStringConvertible {
    let description: String
    let detection: BrewDetectionState
    let absence: InstalledAbsence

    static let all: [UnavailableTapScenario] = {
        let invalidPath = URL(fileURLWithPath: "/configured/not-brew")
        let missingPath = URL(fileURLWithPath: "/configured/missing-brew")
        let rejection = BrewValidationError.notExecutable(invalidPath)
        return [
            UnavailableTapScenario(
                description: "absent",
                detection: .absent,
                absence: .notInstalled(.standard)
            ),
            UnavailableTapScenario(
                description: "invalid",
                detection: .invalid(invalidPath, rejection),
                absence: .configuredPathRejected(invalidPath, rejection)
            ),
            UnavailableTapScenario(
                description: "configured path missing",
                detection: .configuredPathMissing(missingPath),
                absence: .configuredPathMissing(missingPath)
            )
        ]
    }()
}

private enum TapManagementAction: String, CaseIterable, Sendable {
    case refresh
    case filter
    case installedHandoff = "Installed handoff"
    case canonicalAdd = "canonical add"
    case plainUntap = "plain untap"
    case eligibleForceUntap = "eligible force untap"
}
