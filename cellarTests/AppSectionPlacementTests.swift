//
//  AppSectionPlacementTests.swift
//  cellarTests
//

import Foundation
import Testing

@testable import cellar

/// Where Health sits, and what the sidebar switch may not do about it (D4).
///
/// D4 is carried by this change's `tasks.md` rather than by a requirement — the
/// tenth `AppSection` case, Home's retention, and the resolution of the deferred
/// question at `AppSection.swift:17–20` are app-side placement decisions with no
/// `CellarCore` behaviour. This file is their only home, so a later reader does
/// not have to reconstruct the decision from the enum's case order alone.
@Suite("AppSection placement")
struct AppSectionPlacementTests {
    // MARK: - 9.1 — the tenth case, and where it sits

    @MainActor
    @Test("Health sits between Cleanup and Security in declaration order")
    func healthSitsBetweenCleanupAndSecurity() throws {
        let order = AppSection.allCases
        // Ten M5-era sections, plus the four the design document promoted to
        // sidebar rows — favorites, updates, brewfile, and settings — plus the
        // four cask-discovery pages the CaskHub port added, plus the one
        // data-driven category page behind the sidebar's category rows, plus
        // the three formula-discovery pages that mirror the cask ones, minus
        // the original Discover section: the maintainer retired it
        // (2026-08-17) once the two Discover groups covered its job with
        // live analytics rather than a static curated list, plus the tap
        // search surface the 2026-08-25 scope change gave its own row beside
        // Search catalog.
        #expect(order.count == 22)

        let health = try #require(order.firstIndex(of: .health))
        let cleanup = try #require(order.firstIndex(of: .cleanup))
        let security = try #require(order.firstIndex(of: .security))
        let services = try #require(order.firstIndex(of: .services))

        // Adjacent to Cleanup on one side and Security on the other, which is
        // what places it between Services and Security in declaration order
        // (PRD §5). The rendered sidebar reads `sidebarGroups`, asserted below.
        #expect(health == cleanup + 1)
        #expect(health + 1 == security)
        #expect(services < health)

        #expect(AppSection.health.title == "Health")
        #expect(AppSection.health.systemImage == "waveform.path.ecg")
        #expect(AppSection.health.rawValue == "health")
        // The sidebar identifier a UI test queries by.
        #expect(order.map(\.rawValue) == [
            "home", "browse", "tapSearch",
            "caskBrowse", "caskFeatured", "caskTopCharts", "caskRecentlyAdded",
            "caskCategory",
            "formulaBrowse", "formulaFeatured", "formulaTopCharts",
            "installed", "favorites", "updates",
            "taps", "services", "cleanup", "health", "security", "brewfile",
            "history", "settings"
        ])
    }

    /// The rendered sidebar arrangement: the design document's four labelled
    /// groups plus a Settings footer, together covering every section exactly
    /// once — a section outside the arrangement would be unreachable.
    ///
    /// **Amended twice, never weakened.** When the category pages landed,
    /// `.caskCategory` was the coverage rule's one deliberate exception: a
    /// single case behind eighteen data-driven CATEGORIES rows, in no fixed
    /// group. The maintainer then retired those rows (2026-08-17) — eighteen
    /// rows cost more sidebar than they earned — and gave the section a static
    /// "Categories" row in Discover Casks instead, opening a list-and-detail
    /// arrangement: categories in the list pane, the selected category's page
    /// in the detail. The row no longer points at an arbitrary category; it
    /// points at the list of them, so the old objection to a static row no
    /// longer applies, and the coverage rule holds with no exception at all.
    @MainActor
    @Test("The sidebar groups plus the footer cover every section exactly once")
    func sidebarGroupsCoverEverySectionOnce() {
        let arranged = AppSection.sidebarGroups.flatMap(\.sections) + AppSection.sidebarFooter
        #expect(arranged.count == AppSection.allCases.count)
        #expect(Set(arranged) == Set(AppSection.allCases))

        #expect(AppSection.sidebarGroups.map(\.title) == [
            "Overview", "Discover Casks", "Discover Formulae", "Packages", "Insights", "Manage"
        ])
        #expect(AppSection.sidebarFooter == [.settings])
        // Categories closes Discover Casks, after Recently Added — the row
        // that reclaimed the data-driven CATEGORIES group's vertical space.
        #expect(AppSection.sidebarGroups[1].sections == [
            .caskBrowse, .caskFeatured, .caskTopCharts, .caskRecentlyAdded, .caskCategory,
        ])
        // The formula mirror carries only the pages its data can honestly
        // fill: no added dates and no categories exist for formulae, so
        // Recently Added and Categories have no formula siblings.
        #expect(AppSection.sidebarGroups[2].sections == [
            .formulaBrowse, .formulaFeatured, .formulaTopCharts,
        ])
        // Health leads Insights, which is the design's placement of PRD §5's
        // "between Services and Security": Services closes the group before it,
        // Security follows it.
        #expect(AppSection.sidebarGroups[4].sections == [.health, .security, .cleanup])
        // Overview gained the tap search surface beside Search catalog: two
        // query surfaces, siblings, in the group a user lands in.
        #expect(AppSection.sidebarGroups[0].sections == [.home, .browse, .tapSearch])
    }

    /// Home keeps its place at the head of the sidebar, and now holds the
    /// landing spot.
    ///
    /// **Rewritten, never deleted.** The landing was `.browse` from M1 until
    /// the design port; the F13 note that used to live here pinned that literal
    /// so a move would be a deliberate decision recorded on this line — and
    /// this is that recording. The maintainer moved the landing to `.home`
    /// (2026-08-07): the design document opens on Home, and Home now carries
    /// the attention cards and snapshot that make a landing worth having.
    /// Health still did not take it.
    @MainActor
    @Test("Home leads the sidebar and holds the landing section")
    func homeLeadsAndHoldsTheLandingSection() throws {
        #expect(AppSection.allCases.first == .home)

        let landing = try #require(try AppSectionSourceScan.shellDefaultSection())
        #expect(landing != "health", "the Health section took the landing spot")
        #expect(landing != "security")
        // The shipped value, pinned so a silent future move fails here rather
        // than passing unnoticed.
        #expect(landing == "home")
    }

    // MARK: - 9.2 — no `default` arm in an AppSection switch

    /// A `default:` is what would let the eleventh case ship unrendered.
    ///
    /// Nine sections shipped with three exhaustive switches over them — two in
    /// `ContentView` and two in `AppSection` itself. Each one is a place the
    /// compiler currently forces a decision about a new section; a single
    /// `default:` would remove that, and the failure mode is silent: the app
    /// builds, the sidebar row appears, and the column behind it renders whatever
    /// the default arm happened to say.
    @MainActor
    @Test("Every AppSection switch covers .health with no default arm")
    func everyAppSectionSwitchCoversHealthWithoutADefault() throws {
        let sources = try AppSecuritySources.load()
        var switches: [AppSectionSourceScan.Switch] = []
        for source in sources {
            switches.append(contentsOf: AppSectionSourceScan.appSectionSwitches(in: source.code, file: source.name))
        }

        // The positive anchor. A scan that opened nothing, or whose detector
        // stopped recognising an `AppSection` switch, must fail here rather than
        // report a clean sweep of zero switches.
        #expect(switches.count >= 4, "only found \(switches.map(\.file)); the detector read nothing")
        #expect(switches.contains { $0.file == "ContentView.swift" })
        #expect(switches.contains { $0.file == "AppSection.swift" })
        #expect(
            switches.filter { $0.file == "ContentView.swift" }.count == 3,
            "ContentView's content, detail and title-bar-accessory switches are all meant to be found"
        )

        for found in switches {
            #expect(
                found.body.contains("case .health"),
                "\(found.file) switches over AppSection without covering .health"
            )
            #expect(
                found.hasDefaultArm == false,
                "\(found.file) has a `default:` in an AppSection switch; the eleventh case would ship unrendered"
            )
        }
    }

    /// Settings leads with the same pinned capsule card as every other
    /// section: the shell's `ShellTitleBar` with the title and the shared
    /// Refresh/Activity pair. Membership in **both** sets is what produces
    /// that: `shellTitleBarSections` pins the bar, and `pinnedHeaderSections`
    /// keeps the toolbar row from saying it all twice above it.
    ///
    /// With Settings in, the pinned-header set covers the whole vocabulary —
    /// asserted as full coverage rather than one membership, so a section
    /// added later cannot quietly ship with toolbar-row chrome nobody chose.
    @MainActor
    @Test("Settings leads with the shell title bar, and every section pins a capsule header")
    func settingsLeadsWithTheShellTitleBar() throws {
        let source = AppSecuritySources.stripComments(
            from: try AppSectionSourceScan.rawSource(named: "ContentView.swift")
        )
        let pinned = try #require(
            Self.setLiteral(named: "pinnedHeaderSections", in: source),
            "ContentView no longer declares the pinned-header set"
        )
        let titleBar = try #require(
            Self.setLiteral(named: "shellTitleBarSections", in: source),
            "ContentView no longer declares the shell-title-bar set"
        )

        #expect(titleBar.contains(".settings"), "Settings does not pin the shell title bar")
        for section in AppSection.allCases {
            #expect(
                pinned.contains(".\(section.rawValue)"),
                "\(section.rawValue) still draws toolbar-row chrome instead of a pinned header"
            )
        }
    }

    /// The `[...]` literal assigned to the named set, or `nil` when absent.
    private static func setLiteral(named name: String, in source: String) -> String? {
        guard let declaration = source.range(of: "let \(name): Set<AppSection> = [") else {
            return nil
        }
        guard let close = source[declaration.upperBound...].firstIndex(of: "]") else { return nil }
        return String(source[declaration.upperBound..<close])
    }

    /// The violation control. Without it the sweep above passes just as happily
    /// against a detector that recognises nothing at all.
    @MainActor
    @Test("The switch detector sees a default arm when there is one")
    func theSwitchDetectorSeesADefaultArm() {
        let offender = """
        var body: some View {
            switch section {
            case .home: HomeView()
            case .cleanup: CleanupView()
            case .health: HealthView()
            case .security: SecurityView()
            default: EmptyView()
            }
        }
        """
        let found = AppSectionSourceScan.appSectionSwitches(in: offender, file: "Offender.swift")
        #expect(found.count == 1)
        #expect(found.first?.hasDefaultArm == true)

        let missing = """
        switch section {
        case .home: HomeView()
        case .cleanup: CleanupView()
        case .security: SecurityView()
        }
        """
        let secondFound = AppSectionSourceScan.appSectionSwitches(in: missing, file: "Missing.swift")
        #expect(secondFound.count == 1)
        #expect(secondFound.first?.body.contains("case .health") == false)
        #expect(secondFound.first?.hasDefaultArm == false)

        // And it does not fire on a switch over something else that merely
        // *mentions* a section — `ServiceDetailView` has exactly that shape.
        let unrelated = """
        switch notice {
        case .nothingSelected, .reading: AppSection.services.systemImage
        case .failed: "exclamationmark.triangle"
        }
        """
        #expect(AppSectionSourceScan.appSectionSwitches(in: unrelated, file: "Unrelated.swift").isEmpty)
    }

    /// The deferred question at `AppSection.swift:17–20` is marked **resolved**,
    /// not deleted — and the resolution records what shipped.
    ///
    /// A silent deletion is indistinguishable from never having decided. The
    /// comment is the only record that the question was asked, and D4 is the
    /// answer, so the answer replaces the question in place.
    ///
    /// **Corrected for finding F13.** The first resolution wrote "Home keeps the
    /// landing spot", which is not what the shell does: `ContentView` has landed
    /// on `.browse` since M1, and `:75` above pins that literal. A record that
    /// contradicts a sibling assertion in this same file is worse than no record,
    /// so the comment now says what D4 actually settled — Home stays a section,
    /// Browse stays the landing, and Health took neither.
    @MainActor
    @Test("The deferred Home question is recorded as resolved, and records what shipped")
    func theDeferredHomeQuestionIsRecordedAsResolved() throws {
        let text = try AppSectionSourceScan.rawSource(named: "Shell/AppSection.swift")

        #expect(text.contains("D4"), "the resolution no longer names the decision it settles")
        // The landing moved to Home in the design port; the comment must
        // record the move rather than restate the superseded M1 value.
        #expect(text.lowercased().contains("now takes the landing"))
        #expect(text.lowercased().contains("moved it to `.home`"))
        #expect(
            text.contains("slice 5's decision") == false,
            "the question is still deferred; D4 settled it"
        )
        #expect(
            text.contains("for now") == false,
            "\"for now\" is the deferral this change was supposed to resolve"
        )
    }
}

// MARK: - The scanner

/// Reads the app target's own sources to make claims about shapes the compiler
/// cannot be asked about from inside the target.
///
/// The `SnoozeGuardTests` idiom, restated for `cellar/`: comments stripped, a
/// positive anchor per claim, and a violation control beside every prohibition.
nonisolated enum AppSectionSourceScan {
    struct Switch: Sendable, Hashable {
        let file: String
        let body: String
        var hasDefaultArm: Bool { Self.containsDefaultArm(body) }

        static func containsDefaultArm(_ body: String) -> Bool {
            body.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed == "default:" || trimmed.hasPrefix("default:")
            }
        }
    }

    /// A file read verbatim — comments included — for claims *about* a comment.
    static func rawSource(named relativePath: String) throws -> String {
        try String(
            contentsOf: AppSecuritySources.directory.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    /// The shell's initial sidebar selection, read off `ContentView`'s declaration.
    ///
    /// Read from the source rather than by rendering: the value is a `private`
    /// `@State` initial value, so there is no way to observe it from a test
    /// without standing up a window, and standing up a window to learn a constant
    /// is how a placement test becomes a UI test.
    static func shellDefaultSection() throws -> String? {
        let source = AppSecuritySources.stripComments(from: try rawSource(named: "ContentView.swift"))
        guard let line = source
            .split(separator: "\n")
            .first(where: { $0.contains("var section: AppSection = .") })
        else { return nil }
        guard let marker = line.range(of: "AppSection = .") else { return nil }
        return String(line[marker.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every `switch` in `source` whose case labels are `AppSection` cases.
    ///
    /// Identified by what it decides rather than by what it is named, so a switch
    /// over `self` inside `AppSection` and a switch over `section` inside
    /// `ContentView` are both found, and a switch over something else that merely
    /// mentions `AppSection.services` is not.
    static func appSectionSwitches(in source: String, file: String) -> [Switch] {
        var results: [Switch] = []
        var searchStart = source.startIndex

        while let keyword = source.range(of: "switch ", range: searchStart..<source.endIndex) {
            searchStart = keyword.upperBound
            guard let open = source[keyword.upperBound...].firstIndex(of: "{") else { break }
            guard let close = matchingBrace(in: source, openedAt: open) else { break }

            let body = String(source[source.index(after: open)..<close])
            if isAppSectionSwitch(body) {
                results.append(Switch(file: file, body: body))
            }
            searchStart = source.index(after: open)
        }
        return results
    }

    /// At least two distinct `AppSection` case labels, and no label that is not
    /// one. Two, because a single `case .security:` is also a `SecuritySection`
    /// label and a single match would be a coincidence rather than an
    /// identification.
    private static func isAppSectionSwitch(_ body: String) -> Bool {
        let labels = caseLabels(in: body)
        guard labels.isEmpty == false else { return false }
        let sections = Set(AppSection.allCases.map(\.rawValue))
        // Names in `sections` that this switch decides on.
        let matched = labels.filter { sections.contains($0) }
        return matched.count >= 2 && matched.count == labels.count
    }

    /// The identifiers a switch's `case .x, .y:` labels name, at this nesting
    /// level only.
    private static func caseLabels(in body: String) -> [String] {
        var labels: [String] = []
        var depth = 0
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // `default:` is detected separately by `hasDefaultArm`; it carries no
            // label to extract, and slicing it as though it did is how the
            // detector stopped recognising the very switch it was pointed at.
            if depth == 0, line.hasPrefix("case ") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let head = String(line[line.index(line.startIndex, offsetBy: 5)..<colon])
                for token in head.split(separator: ",") {
                    let name = token.trimmingCharacters(in: .whitespaces)
                    guard name.hasPrefix(".") else { return [] }
                    labels.append(String(name.dropFirst()))
                }
            }
            depth += rawLine.filter { $0 == "{" }.count
            depth -= rawLine.filter { $0 == "}" }.count
        }
        return labels
    }

    /// Brace matching that does not count a brace inside a string literal.
    private static func matchingBrace(in source: String, openedAt open: String.Index) -> String.Index? {
        var depth = 0
        var index = open
        var inString = false

        while index < source.endIndex {
            let character = source[index]
            if inString {
                if character == "\\" {
                    index = source.index(after: index)
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
