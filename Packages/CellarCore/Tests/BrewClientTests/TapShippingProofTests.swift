import CellarTestSupport
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
        #expect(center.isAvailable == false)
        #expect(
            TapProjection.state(loadState: store.state, inventory: store.inventory)
                == .unavailable(scenario.absence)
        )
        #expect(addItems.count == 1)
        #expect((addItems + [untapItem]).allSatisfy { $0.outcome == .launchFailed })
        #expect(launcher.launchCount == 0, "\(scenario) spawned a tap process")
        #expect(launcher.specs.isEmpty, "\(scenario) constructed a process launch")
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
        #expect(launcher.specs.isEmpty)

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

    @Test("The complete tap action surface stays bounded to its four capabilities")
    func completeActionSurfaceIsBounded() async throws {
        let launcher = actionSurfaceLauncher()
        let store = TapStore(source: BrewTapPayloadSource(launcher: launcher))
        let installed = try installedInventory()
        var commands: [TapCommand] = []

        // TM11 :392-398 — the enumerated surface, in the order the requirement
        // lists it. It grows to eight deliberately (R9): a pinned set that fails
        // loudly the day a capability appears is the whole point of pinning it.
        #expect(TapManagementAction.allCases.map(\.rawValue) == [
            "refresh", "filter", "Installed handoff", "canonical add", "plain untap",
            "eligible force untap", "trust", "untrust"
        ])
        for action in TapManagementAction.allCases {
            commands.append(contentsOf: try await exercise(action, store: store, installed: installed))
        }

        #expect(launcher.specs.map(\.arguments) == [["tap-info", "--installed", "--json"]])
        // Seven commands for eight actions: each removal is a revocation
        // followed by the removal itself (TM7 :216-221).
        #expect(commands.map(\.arguments) == [
            ["tap", "other/home"],
            ["untrust", "acme/tools"],
            ["untap", "acme/tools"],
            ["untrust", "acme/tools"],
            ["untap", "--force", "acme/tools"],
            ["trust", "acme/tools"],
            ["untrust", "acme/tools"]
        ])
        #expect(commands.map(\.invalidates) == [
            .taps,
            [.taps, .installedInventory],
            .taps,
            [.taps, .installedInventory],
            [.taps, .installedInventory, .diskUsage],
            [.taps, .installedInventory],
            [.taps, .installedInventory]
        ])
        #expect(commands.allSatisfy { $0.packageID == nil })
        try assertBoundedUIControls()
    }

    // MARK: - TM12 / TM11 — what the trust surface may and may not do

    /// TM12 :444-450. A Homebrew with no trust concept reports nothing, and the
    /// honest answer to "is this tap trusted?" is then silence — not a badge, not
    /// a control, and above all not a `brew trust` that such a brew cannot run.
    ///
    /// The second half is the amended clause: TM7's revocation before removal is
    /// **unconditional**, so untapping the very same tap is unaffected. The two
    /// rules are about different things — a control the user presses, and a
    /// command an action always submits.
    @Test("An unreported tap offers no control and spawns nothing")
    func anUnreportedTapOffersNoControlAndSpawnsNothing() async throws {
        let launcher = RecordingProcessLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: TestInstallation.appleSilicon)
        // `trust` defaults to `.unreported`, which is exactly what a Homebrew
        // that never sends the key produces.
        let record = TapRecord(name: "acme/tools", repository: "tools")
        let presentation = TapProjection.trust(for: record)

        #expect(record.trust == .unreported)
        #expect(presentation.badge == nil)
        #expect(presentation.canGrant == false)
        #expect(presentation.canRevoke == false)

        // Invoking either control is what the view does when its gate is open:
        // build the command, submit it. With both gates closed nothing is built,
        // so nothing can be spawned.
        var built: [TapCommand] = []
        if presentation.canGrant, let grant = TapCommand.trust(record.name) { built.append(grant) }
        if presentation.canRevoke, let revoke = TapCommand.untrust(record.name) { built.append(revoke) }
        for command in built { _ = center.submit(command) }
        await drain()

        #expect(built.isEmpty, "an unreported tap built a trust command")
        #expect(launcher.specs.isEmpty, "an unreported tap's controls spawned a process")

        // …while untapping the same tap is untouched by any of that: TM7's
        // revocation is unconditional, so it is still submitted here — where it
        // may well fail, which TM12 :426-428 explicitly accepts.
        center.submitSequence(try #require(TapCommand.removal(of: record.name)))
        await TestPoll.until(launcher.launchCount >= 2)
        await drain()
        #expect(launcher.specs.map(\.arguments) == [
            ["untrust", "acme/tools"],
            ["untap", "acme/tools"]
        ])
    }

    /// TM11 :400-406. Showing a reported state and offering brew's own grant is
    /// not tap security scanning. The line is drawn by vocabulary as much as by
    /// behaviour: the moment this surface says a tap looks safe, or ranks one
    /// above another, it has made a judgement it has no evidence for.
    @Test("Trust is a reported state and a grant, never a verdict")
    func trustIsAReportedStateAndAGrantNeverAVerdict() throws {
        let record = TapRecord(name: "acme/tools", repository: "tools", trust: .untrusted)

        // Everything presented is either the state brew reported…
        let presentation = TapProjection.trust(for: record)
        #expect(presentation.badge == "Untrusted")
        // …or a control submitting brew's own grant or revocation, verbatim.
        #expect(try #require(TapCommand.trust(record.name)).arguments == ["trust", "acme/tools"])
        #expect(try #require(TapCommand.untrust(record.name)).arguments == ["untrust", "acme/tools"])

        // And nothing anywhere in the surface inspects, scores or recommends.
        var sources = try tapUISources()
        sources.append(contentsOf: try coreTrustSources())
        #expect(sources.count == 4, "the trust surface scan lost a file")
        for source in sources {
            for verdict in [
                "score", "ranking", "recommend", "reputation", "verdict",
                "suspicious", "malicious", "unsafe", "audit", "vetted", "reviewed"
            ] {
                #expect(
                    source.code.localizedCaseInsensitiveContains(verdict) == false,
                    "\(source.name) passes judgement on a tap's contents: \(verdict)"
                )
            }
        }
    }

    // MARK: - TM12 — one projection, two surfaces

    /// TM12 :460-465 — exactly one projection supplies the trust presentation
    /// the list row and the detail header consume, "so the two cannot drift".
    /// Asserted structurally rather than by rendering: two views computing the
    /// same badge independently is precisely the drift the requirement forbids,
    /// and it would still pass a per-view rendering test on the day they
    /// disagree.
    @Test("The list row and the detail header read one trust projection")
    func listRowAndDetailHeaderReadOneTrustProjection() throws {
        let sources = try tapUISources()

        // Positively anchored: the scan really did find both files.
        #expect(sources.map(\.name).sorted() == ["TapDetailView.swift", "TapsListView.swift"])

        for source in sources {
            #expect(
                source.code.contains("TapProjection.trust(for:"),
                "\(source.name) does not read the shared trust projection"
            )
            #expect(
                source.code.contains("\"Untrusted\"") == false,
                "\(source.name) composes the badge string locally instead of reading the projection"
            )
            for local in [".trust ==", ".trust !=", "case .untrusted", "case .trusted", "case .unreported"] {
                #expect(
                    source.code.contains(local) == false,
                    "\(source.name) derives a trust condition locally: \(local)"
                )
            }
        }
    }

    /// Returns every command the action submits, in submission order — a list
    /// rather than one optional command, because an action is not the same thing
    /// as a command and TM7's removal is two of them.
    private func exercise(
        _ action: TapManagementAction,
        store: TapStore,
        installed: InstalledInventory
    ) async throws -> [TapCommand] {
        switch action {
        case .refresh:
            await store.refresh(using: TestInstallation.appleSilicon)
            #expect(store.state == .loaded)
            return []
        case .filter:
            let packages = try packages(store: store, installed: installed)
            #expect(
                TapProjection.filter(packages, query: "other", kind: .formula)
                    .map(\.displayName) == ["other"]
            )
            return []
        case .installedHandoff:
            let packages = try packages(store: store, installed: installed)
            #expect(
                packages.first(where: { $0.displayName == "widget" })?.installedHandoff
                    == PackageID(kind: .formula, name: "widget")
            )
            return []
        case .canonicalAdd:
            let target = ["other", "home"].joined(separator: "/")
            guard let command = TapCommand.add(target) else {
                Issue.record("canonical add was unavailable")
                return []
            }
            return [command]
        case .plainUntap:
            let target = ["acme", "tools"].joined(separator: "/")
            guard let commands = TapCommand.removal(of: target) else {
                Issue.record("plain untap was unavailable")
                return []
            }
            return commands
        case .trust:
            let target = ["acme", "tools"].joined(separator: "/")
            guard let command = TapCommand.trust(target) else {
                Issue.record("trust was unavailable")
                return []
            }
            return [command]
        case .untrust:
            let target = ["acme", "tools"].joined(separator: "/")
            guard let command = TapCommand.untrust(target) else {
                Issue.record("untrust was unavailable")
                return []
            }
            return [command]
        case .eligibleForceUntap:
            let tap = try #require(TapName("acme/tools"))
            let affected = Set(
                try packages(store: store, installed: installed).compactMap(\.installedHandoff)
            )
            guard let commands = TapCommand.forcedRemoval(evidence: ForceUntapEvidence(
                tap: tap,
                affected: affected,
                isComplete: true
            )) else {
                Issue.record("eligible force untap was unavailable")
                return []
            }
            return commands
        }
    }

    private func packages(
        store: TapStore,
        installed: InstalledInventory
    ) throws -> [TapPackage] {
        let tap = try #require(store.inventory.taps.first)
        return TapProjection.packages(for: tap, installed: installed)
    }

    private struct TapUISource {
        let name: String
        let code: String
    }

    private func coreTrustSources() throws -> [TapUISource] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try ["TapProjection.swift", "TapCommand.swift"].map { file in
            TapUISource(
                name: file,
                code: try String(
                    contentsOf: root.appendingPathComponent("Sources/BrewClient/\(file)"),
                    encoding: .utf8
                )
            )
        }
    }

    private func tapUISources() throws -> [TapUISource] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try ["TapsListView.swift", "TapDetailView.swift"].map { file in
            TapUISource(
                name: file,
                code: try String(
                    contentsOf: root.appendingPathComponent("cellar/Taps/\(file)"),
                    encoding: .utf8
                )
            )
        }
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
            "Add Tap", "Untap", "Force Untap", "Show in Installed", "Trust", "Untrust"
        ])
        #expect(tapUI.contains("Button {") == false, "an unenumerated dynamic tap button exists")

        for excludedCapability in [
            "Install package", "Search catalog", "Clone official source",
            "Security scan", "Git management", "Cleanup", "Disk usage", "Service behavior",
            // The M5 D3 carve-out is repealed (2026-08-17): the Brewfile
            // section owns its own sidebar place and both affordances now,
            // so the word — and with it any Brewfile surface or logic — is
            // excluded here outright again.
            "Brewfile"
        ] {
            #expect(
                tapUI.localizedCaseInsensitiveContains(excludedCapability) == false,
                "excluded capability appeared in tap UI: \(excludedCapability)"
            )
        }

        // No sheets and no destination: every tap action acts in place.
        #expect(tapUI.contains(".sheet(isPresented:") == false)
        #expect(tapUI.contains("navigationDestination") == false)
    }

    private func staticButtonLabels(in source: String) throws -> Set<String> {
        let expression = try NSRegularExpression(pattern: #"Button\("([^"]+)""#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(expression.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        })
    }

    private func drain() async {
        for _ in 0..<500 { await Task.yield() }
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
    case trust
    case untrust
}
