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
        // Seven commands for eight actions: each removal is the removal itself
        // followed by the revocation that only a successful removal earns
        // (TM7 :216-221, D4).
        #expect(commands.map(\.arguments) == [
            ["tap", "other/home"],
            ["untap", "acme/tools"],
            ["untrust", "acme/tools"],
            ["untap", "--force", "acme/tools"],
            ["untrust", "acme/tools"],
            ["trust", "acme/tools"],
            ["untrust", "acme/tools"]
        ])
        #expect(commands.map(\.invalidates) == [
            .taps,
            .taps,
            [.taps, .installedInventory],
            [.taps, .installedInventory, .diskUsage],
            [.taps, .installedInventory],
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
        // revocation is unconditional, so a removal brew accepts is still
        // followed by it here — where it may well fail, which TM12 :426-428
        // explicitly accepts. The whole action still reaches the centre as one
        // dependent sequence, not as two independent submissions.
        #expect(
            center.submitDependentSequence(try #require(TapCommand.removal(of: record.name))) == nil,
            "a plain untap asked for a confirmation"
        )
        await TestPoll.until(launcher.launchCount >= 2)
        await drain()
        #expect(launcher.specs.map(\.arguments) == [
            ["untap", "acme/tools"],
            ["untrust", "acme/tools"]
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

    // MARK: - package-trust D-d / TM12.7 — the badge is untouched

    /// **Binding.** The count line is an *additional* component beside the
    /// summary, never a replacement, a qualifier or a restyling of the badge.
    /// Asserted twice over: by value, for every report state, and structurally,
    /// because a later change could make the badge depend on the report without
    /// changing any of today's values.
    @Test("The tap badge and summary are unchanged by grants")
    func theTapBadgeAndSummaryAreUnchangedByGrants() throws {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget", "acme/tools/helper"],
            caskTokens: ["acme/tools/desk"],
            trust: .untrusted
        )
        let states: [TrustGrantState] = [
            .unreported,
            .reported(TrustGrantLedger(declaredNamespaces: ["formulae", "casks"])),
            .reported(TrustGrantLedger(formulae: ["acme/tools/widget"])),
            .reported(TrustGrantLedger(taps: ["acme/tools"])),
            .reported(TrustGrantLedger(
                formulae: ["acme/tools/widget", "acme/tools/helper"],
                casks: ["acme/tools/desk"]
            ))
        ]

        let badge = TapProjection.trust(for: tap)
        let summary = TapProjection.packageSummary(for: tap)
        #expect(badge.badge == "Untrusted")
        #expect(summary == "2 formulae · 1 cask")
        #expect(states.count == 5, "the report-state enumeration collapsed")

        for state in states {
            #expect(TapProjection.trust(for: tap) == badge, "\(state) moved the badge")
            #expect(TapProjection.packageSummary(for: tap) == summary, "\(state) moved the summary")
        }
        // Positively anchored: the count line really does vary across those
        // states, so the two expectations above are not both trivially constant.
        #expect(Set(states.map { TapProjection.grants(for: tap, in: $0).countLine }) == [
            nil, "1 trusted individually", "3 trusted individually"
        ])

        // Structurally: neither shipped function can see a report at all.
        let projection = try coreTrustSources()
            .first { $0.name == "TapProjection.swift" }
            .map(\.code)
        let source = try #require(projection)
        for signature in [
            "public static func trust(for tap: TapRecord) -> TapTrustPresentation {",
            "public static func packageSummary(for tap: TapRecord) -> String {"
        ] {
            #expect(source.contains(signature), "a shipped projection signature moved: \(signature)")
        }
    }

    // MARK: - PT7 :383-421 — the whole surface grants and revokes nothing

    /// **D-f.** The prohibition is a property of the surface, not of any one
    /// screen, so it is asserted as an absence: this change adds **no action**,
    /// and every value the per-package surface produces is a string.
    @Test("No new control submits anything and the surface is display only")
    func noNewControlSubmitsAnythingAndTheSurfaceIsDisplayOnly() async throws {
        let launcher = RecordingProcessLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: TestInstallation.appleSilicon)

        // The action set is unchanged: eight, in TM11's order. This change adds
        // no ninth, which is why `tap-management` TM11 needed no delta.
        #expect(TapManagementAction.allCases.map(\.rawValue) == [
            "refresh", "filter", "Installed handoff", "canonical add", "plain untap",
            "eligible force untap", "trust", "untrust"
        ])

        // Every per-package surface, invoked. The enumeration is the four entry
        // points this change adds, and it is asserted non-vacuous below.
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"],
            caskTokens: ["acme/tools/desk"],
            trust: .untrusted
        )
        let report = TrustGrantState.reported(TrustGrantLedger(
            formulae: ["acme/tools/widget", "nobody/tools/lost"],
            casks: ["acme/tools/desk"],
            taps: ["ghost/tools"],
            commands: ["acme/tools/thing"]
        ))
        var produced: [String] = []
        let presentation = TapProjection.grants(for: tap, in: report)
        produced.append(contentsOf: [presentation.countLine].compactMap(\.self))
        produced.append(TapProjection.grantMarker)
        let section = TapProjection.unattributedSection(in: report, taps: [tap])
        produced.append(section.title)
        produced.append(contentsOf: [section.sentence].compactMap(\.self))
        produced.append(contentsOf: section.groups.flatMap { [$0.title] + $0.entries })
        _ = TapProjection.grantsIndividually(
            PackageID(kind: .cask, name: "desk"),
            publishedBy: tap.name,
            in: report
        )
        _ = TapProjection.accounting(
            of: try #require(report.ledger),
            taps: [tap]
        )
        await drain()

        // Non-vacuous: the surface really did produce something.
        #expect(produced.count >= 8, "the per-package surface enumeration collapsed")
        #expect(produced.contains("2 trusted individually"))
        #expect(produced.contains("Trusted individually"))
        // …and nothing it did built or spawned a process.
        #expect(launcher.launchCount == 0, "a per-package surface spawned a process")
        #expect(launcher.specs.isEmpty, "a per-package surface constructed a process launch")

        // The UI stays bounded to the same six static buttons, with no dynamic
        // button anywhere — which is what makes "every interactive element is a
        // navigation, filter, copy or refresh affordance" checkable at all.
        try assertBoundedUIControls()
    }

    /// **PT6 :334-344, TM11, R3.** Every string is either the state brew
    /// reported or an accounting of it. Nothing here inspects a package.
    @Test("The capability sweep inspects control labels, never prose")
    func capabilitySweepInspectsControlLabelsNotProse() throws {
        // The pre-#90 official-source pane cross-referenced Search catalog in
        // prose; that is a pointer to another section, not a control for it.
        let prose = """
        Text("Browse and install its packages from Search catalog.")
        Button("Untap") { untap(tap) }
        """
        #expect(try excludedCapabilityViolations(in: prose) == [])

        let controls = """
        Button("Search catalog") { openSearch() }
        Menu("Cleanup") { EmptyView() }
        Toggle("Security scan", isOn: $scan)
        Link("Disk usage", destination: url)
        NavigationLink("Brewfile") { EmptyView() }
        """
        #expect(try excludedCapabilityViolations(in: controls) == [
            "Search catalog", "Security scan", "Cleanup", "Disk usage", "Brewfile"
        ])
    }

    @Test("Every per-package string is positive and never a verdict")
    func everyPerPackageStringIsPositiveAndNeverAVerdict() throws {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"],
            caskTokens: ["acme/tools/desk"]
        )
        let states: [TrustGrantState] = [
            .unreported,
            .reported(TrustGrantLedger(declaredNamespaces: ["formulae", "casks"])),
            .reported(TrustGrantLedger(
                formulae: ["acme/tools/widget", "nobody/tools/lost"],
                casks: ["acme/tools/desk"],
                taps: ["ghost/tools"],
                commands: ["acme/tools/thing"]
            ))
        ]

        var strings = [TapProjection.grantMarker]
        for state in states {
            strings.append(contentsOf: [TapProjection.grants(for: tap, in: state).countLine]
                .compactMap(\.self))
            let section = TapProjection.unattributedSection(in: state, taps: [tap])
            strings.append(section.title)
            strings.append(contentsOf: [section.sentence].compactMap(\.self))
            strings.append(contentsOf: section.groups.map(\.title))
        }

        // Non-vacuous, and it really did reach all three report states.
        #expect(strings.count >= 10, "the string enumeration collapsed to \(strings.count)")
        #expect(strings.contains("This Homebrew does not report per-package trust."))
        #expect(strings.contains("Homebrew records no packages trusted individually."))
        #expect(strings.contains(
            "Homebrew still records these grants. Cellar shows them; it does not remove them."
        ))

        for line in strings {
            for negative in [
                "untrusted", "unsafe", "unverified", "unprotected", "not trusted",
                "risk", "danger", "warning", "should", "we suggest"
            ] {
                #expect(
                    line.localizedCaseInsensitiveContains(negative) == false,
                    "a per-package string is a judgement: \(line)"
                )
            }
        }

        // And no source behind those strings inspects, scores or recommends.
        var sources = try tapUISources()
        sources.append(contentsOf: try coreTrustSources())
        sources.append(contentsOf: try perPackageSources())
        #expect(sources.count == 8, "the per-package surface scan lost a file")
        for source in sources {
            for judgement in [
                "score", "ranking", "recommend", "reputation", "verdict",
                "suspicious", "malicious", "unsafe", "audit", "vetted", "reviewed"
            ] {
                #expect(
                    source.code.localizedCaseInsensitiveContains(judgement) == false,
                    "\(source.name) passes judgement on a package: \(judgement)"
                )
            }
        }
    }

    /// The per-package sources this change adds, plus the one shipped view it
    /// joins the marker onto.
    private func perPackageSources() throws -> [TapUISource] {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repository = package
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var sources = try ["TrustGrantWire.swift", "TrustGrantPayloadSource.swift", "TrustGrantStore.swift"]
            .map { file in
                TapUISource(
                    name: file,
                    code: try String(
                        contentsOf: package.appendingPathComponent("Sources/BrewClient/\(file)"),
                        encoding: .utf8
                    )
                )
            }
        sources.append(TapUISource(
            name: "PackageDetailView.swift",
            code: try String(
                contentsOf: repository.appendingPathComponent("cellar/Browse/PackageDetailView.swift"),
                encoding: .utf8
            )
        ))
        return sources
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

        // Scoped to control labels: the proof is that the tap surface offers
        // no *control* for these capabilities, not that prose never names them.
        let offered = try excludedCapabilityViolations(in: tapUI)
        #expect(offered.isEmpty, "excluded capability offered as a tap control: \(offered)")

        // No sheets and no destination: every tap action acts in place.
        #expect(tapUI.contains(".sheet(isPresented:") == false)
        #expect(tapUI.contains("navigationDestination") == false)
    }

    /// Capabilities the tap surface must never offer a control for.
    private static let excludedCapabilities = [
        "Install package", "Search catalog", "Clone official source",
        "Security scan", "Git management", "Cleanup", "Disk usage", "Service behavior",
        // The M5 D3 carve-out is repealed (2026-08-17): the Brewfile
        // section owns its own sidebar place and both affordances now,
        // so the word — and with it any Brewfile surface or logic — is
        // excluded here outright again.
        "Brewfile"
    ]

    /// The excluded capabilities the source offers as a control label.
    ///
    /// Only labels count: prose may cross-reference another section (the
    /// official-source pane points at Search), and that is not a control.
    private func excludedCapabilityViolations(in source: String) throws -> [String] {
        let labels = try controlLabels(in: source)
        return Self.excludedCapabilities.filter { capability in
            labels.contains { $0.localizedCaseInsensitiveContains(capability) }
        }
    }

    private func staticButtonLabels(in source: String) throws -> Set<String> {
        try staticLabels(of: "Button", in: source)
    }

    /// Every statically titled control constructor: buttons plus the menus,
    /// toggles, links and navigation links a tap view could otherwise hide
    /// a capability behind.
    private func controlLabels(in source: String) throws -> Set<String> {
        try staticLabels(of: "Button|Menu|Toggle|Link|NavigationLink", in: source)
    }

    private func staticLabels(of constructors: String, in source: String) throws -> Set<String> {
        let expression = try NSRegularExpression(pattern: #"\b(?:"# + constructors + #")\("([^"]+)""#)
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
