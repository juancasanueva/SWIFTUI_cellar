//
//  BulkActionBarTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import Foundation
import Testing

@testable import cellar

/// The bulk bar, which shipped with **no covering tests at all** until this
/// slice widened what it offers (`installed-inventory` II13, II14).
///
/// Two kinds of claim, each tested the way it can actually be proven:
///
/// - **What each control announces** is a value. `BulkActionBarPresentation` is
///   extracted so labels, counts, roles and enablement are provable without
///   rendering anything — the `PackageInspectionRow` idiom.
/// - **What the bar does not contain** is an absence, and only a source scan can
///   make that claim. The scan carries a positive anchor and a violation control,
///   because a bounded-control guard with neither passes loudest when it reads
///   nothing at all.
@Suite("Bulk action bar", .timeLimit(.minutes(1)))
struct BulkActionBarTests {

    // MARK: - 11.4 — each verb's label counts its own eligible set (II14)

    /// One mixed selection, five controls, five different numbers.
    ///
    /// This is the exact shape II14 sc4 names: two unpinned formulae, one pinned
    /// formula and one cask, all outdated and unsnoozed. Pin sees 2, unpin sees 1,
    /// snooze sees all 4, and each number comes from the same projection its own
    /// action submits.
    @Test("Each verb announces its own eligible set over one mixed selection")
    func eachVerbAnnouncesItsOwnEligibleSet() throws {
        let packages = [
            HealthFixtures.package("git", offering: "1.2.3", outdated: true),
            HealthFixtures.package("jq", offering: "1.7.1", outdated: true),
            HealthFixtures.package("hugo", offering: "0.150.0", outdated: true, pinned: true),
            HealthFixtures.package("iterm2", kind: .cask, offering: "3.6.0", outdated: true)
        ]
        let entries = HealthFixtures.entries(packages)
        let order = packages.map(\.id)

        let selection = BulkSelection(selection: order, entries: entries, metadata: nil)
        let snooze = BulkSnoozeSelection(selection: order, entries: entries, metadata: nil)
        let presentation = BulkActionBarPresentation(
            selection: selection,
            snooze: snooze,
            isOperationAvailable: true
        )

        #expect(presentation.control(for: .pin)?.count == 2)
        #expect(presentation.control(for: .unpin)?.count == 1)
        #expect(presentation.snooze.count == 4)
        #expect(presentation.control(for: .upgrade)?.count == 3, "a pinned package is not upgradable")
        #expect(presentation.control(for: .uninstall)?.count == 4)

        // The number announced is the number of ids the action would act on —
        // one projection, read twice, so they cannot drift apart.
        #expect(presentation.control(for: .pin)?.count == selection.ids(for: .pin).count)
        #expect(presentation.control(for: .unpin)?.count == selection.ids(for: .unpin).count)
        #expect(presentation.snooze.count == snooze.snoozable.count)

        // …and the label carries that number, so a user reads it too.
        #expect(presentation.control(for: .pin)?.label == "Pin 2")
        #expect(presentation.control(for: .unpin)?.label == "Unpin 1")
        #expect(presentation.snooze.label.contains("4"))
    }

    @Test("Only uninstall carries the destructive role")
    func onlyUninstallCarriesTheDestructiveRole() throws {
        let packages = [HealthFixtures.package("git", offering: "1.2.3", outdated: true)]
        let entries = HealthFixtures.entries(packages)
        let presentation = BulkActionBarPresentation(
            selection: BulkSelection(selection: packages.map(\.id), entries: entries, metadata: nil),
            snooze: BulkSnoozeSelection(selection: packages.map(\.id), entries: entries, metadata: nil),
            isOperationAvailable: true
        )

        #expect(presentation.controls.filter(\.isDestructive).map(\.label) == ["Uninstall 1"])
        #expect(presentation.snooze.isDestructive == false)
    }

    /// **Unavailable rather than inert** — the failure mode II13 sc5 forbids by
    /// name.
    @Test("An all-cask selection leaves pin and unpin unavailable, not inert")
    func anAllCaskSelectionLeavesPinAndUnpinUnavailable() throws {
        let casks = [
            HealthFixtures.package("iterm2", kind: .cask, offering: "3.6.0", outdated: true),
            HealthFixtures.package("rectangle", kind: .cask, offering: "0.90", outdated: true)
        ]
        let entries = HealthFixtures.entries(casks)
        let order = casks.map(\.id)
        let presentation = BulkActionBarPresentation(
            selection: BulkSelection(selection: order, entries: entries, metadata: nil),
            snooze: BulkSnoozeSelection(selection: order, entries: entries, metadata: nil),
            isOperationAvailable: true
        )

        #expect(presentation.control(for: .pin)?.isEnabled == false)
        #expect(presentation.control(for: .unpin)?.isEnabled == false)
        #expect(presentation.control(for: .pin)?.count == 0)
        // Snooze is not formula-only, so a cask can still be snoozed — which is
        // what makes "each verb derives its own eligible set" a real claim rather
        // than one filter applied five times.
        #expect(presentation.snooze.isEnabled)
        #expect(presentation.snooze.count == 2)
    }

    @Test("An unavailable operation centre disables the mutation verbs and not the snooze")
    func anUnavailableOperationCentreDisablesTheMutationVerbs() throws {
        let packages = [HealthFixtures.package("git", offering: "1.2.3", outdated: true)]
        let entries = HealthFixtures.entries(packages)
        let order = packages.map(\.id)
        let presentation = BulkActionBarPresentation(
            selection: BulkSelection(selection: order, entries: entries, metadata: nil),
            snooze: BulkSnoozeSelection(selection: order, entries: entries, metadata: nil),
            isOperationAvailable: false
        )

        #expect(presentation.controls.filter { $0.label.hasPrefix("Snooze") == false }.allSatisfy { !$0.isEnabled })
        // Snooze spawns nothing, so a missing brew is no reason to withhold it.
        #expect(presentation.snooze.isEnabled)
    }

    // MARK: - 11.5 — the bounded-control guard

    /// Exactly the labels the bar is allowed to offer, and no unbulked verb.
    ///
    /// `favorite` and `note` stay prohibited by II13, and no **service** verb may
    /// appear in a package bulk surface (`service-management` SM4 sc5, SM12: a
    /// service is its own entity and one whose name matches an installed formula
    /// is still not that formula).
    @Test("The bar offers exactly the bulk labels and no unbulked verb")
    func theBarOffersExactlyTheBulkLabelsAndNoUnbulkedVerb() throws {
        let literals = try BulkActionBarSources.stringLiterals().map { $0.lowercased() }

        // The positive anchor. A scan that opened nothing, or whose extractor
        // stopped recognising a literal, fails here instead of reporting a clean
        // sweep of zero literals.
        #expect(literals.isEmpty == false, "the bar's string literals read as empty")
        #expect(literals.contains { $0.contains("snooze") }, "the snooze control's own copy is missing")

        for verb in BulkActionBarSources.unbulkedVerbs {
            #expect(
                literals.contains { $0.contains(verb) } == false,
                "the bulk bar offers \(verb), which has no bulk affordance"
            )
        }
    }

    /// The violation control.
    @Test("The bounded-control guard sees an unbulked verb when there is one")
    func theBoundedControlGuardSeesAnUnbulkedVerb() {
        let offender = """
        Button("Favorite \\(count)") { metadata.toggleFavorite(id) }
        Button("Restart service") { operations.submit(command) }
        """
        let literals = BulkActionBarSources.stringLiterals(in: offender).map { $0.lowercased() }
        #expect(literals.count == 2)
        #expect(BulkActionBarSources.unbulkedVerbs.contains { verb in literals.contains { $0.contains(verb) } })

        // …and it does not fire on the bar as written, or the sweep above would
        // be unsatisfiable rather than satisfied.
        let allowed = BulkActionBarSources.stringLiterals(in: #"Button("Snooze \(count)") { }"#)
            .map { $0.lowercased() }
        #expect(BulkActionBarSources.unbulkedVerbs.contains { verb in allowed.contains { $0.contains(verb) } } == false)
    }

    /// The snooze copy names the count and **never** a duration.
    ///
    /// "Snooze" is the one verb in this app whose ordinary English meaning is a
    /// duration and whose implementation deliberately is not, so the copy rule is
    /// a requirement rather than a preference (LPM4).
    @Test("The snooze copy implies no duration and says what it actually does")
    func theSnoozeCopyImpliesNoDurationAndSaysWhatItDoes() {
        let copy = (BulkSnoozeCopy.label(count: 4) + " " + BulkSnoozeCopy.explanation).lowercased()

        #expect(BulkSnoozeCopy.label(count: 4).contains("4"))
        for duration in [
            "hour", "day", "week", "month", "minute", "later", "remind",
            "until tomorrow", "expire", "duration", "period", "interval", "temporar", "snooze for"
        ] {
            #expect(copy.contains(duration) == false, "the snooze copy implies a \(duration)")
        }
        // And it states what the snooze really does.
        #expect(BulkSnoozeCopy.explanation.lowercased().contains("different version is offered"))
    }

    /// Snooze is a button **beside** the `ForEach`, never a case inside it.
    @Test("The snooze control sits beside the bulk vocabulary, not inside it")
    func theSnoozeControlSitsBesideTheBulkVocabulary() throws {
        let source = try BulkActionBarSources.barSource()
        #expect(source.contains("ForEach(BulkSelection.Action.allCases"))
        #expect(source.contains("BulkSnoozeCopy.label"))

        // The snooze copy is not reachable from inside the `allCases` loop: if it
        // were, it would be a fifth verb in everything but name.
        let loop = try #require(BulkActionBarSources.forEachBody(in: source))
        #expect(loop.contains("snooze") == false, "the snooze control lives inside the bulk vocabulary's ForEach")
        #expect(loop.contains("Snooze") == false)
    }
}

/// Reads the bar and the package sources the guards make claims about.
nonisolated enum BulkActionBarSources {
    /// Every verb with no bulk affordance: the two `installed-inventory`
    /// prohibits outright, and the four `ServiceCommand` publishes.
    static let unbulkedVerbs = ["favorite", "note", "start", "run", "stop", "restart"]

    static func barSource() throws -> String {
        AppSecuritySources.stripComments(
            from: try String(
                contentsOf: AppSecuritySources.directory
                    .appendingPathComponent("Installed/BulkActionBar.swift"),
                encoding: .utf8
            )
        )
    }

    /// A package-root-relative source, comment-stripped.
    static func packageSource(at path: String) throws -> String {
        let root = AppSecuritySources.directory
            .deletingLastPathComponent()
            .appendingPathComponent("Packages/CellarCore")
        return AppSecuritySources.stripComments(
            from: try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        )
    }

    static func stringLiterals() throws -> [String] {
        stringLiterals(in: try barSource())
    }

    /// Every `"…"` literal in `code`, interpolations included verbatim.
    static func stringLiterals(in code: String) -> [String] {
        var found: [String] = []
        var current = ""
        var inString = false
        var index = code.startIndex

        while index < code.endIndex {
            let character = code[index]
            if inString {
                if character == "\\" {
                    let next = code.index(after: index)
                    if next < code.endIndex { current.append(code[next]) }
                    index = next
                } else if character == "\"" {
                    inString = false
                    found.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inString = true
            }
            index = code.index(after: index)
        }
        return found
    }

    /// The body of the `ForEach` over the bulk vocabulary.
    static func forEachBody(in code: String) -> String? {
        guard let marker = code.range(of: "ForEach(BulkSelection.Action.allCases"),
              let open = code[marker.upperBound...].firstIndex(of: "{")
        else { return nil }

        var depth = 0
        var index = open
        while index < code.endIndex {
            if code[index] == "{" { depth += 1 }
            if code[index] == "}" {
                depth -= 1
                if depth == 0 { return String(code[code.index(after: open)..<index]) }
            }
            index = code.index(after: index)
        }
        return nil
    }
}
