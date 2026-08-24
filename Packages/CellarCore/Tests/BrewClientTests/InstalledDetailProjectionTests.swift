import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The reduced detail a package the catalog does not carry gets from its own
/// receipt (installed-inventory II15).
///
/// Every rule here is a rule about **one decoded record**: the projection takes
/// no catalog value, reads no store, spawns no process and consults no clock, so
/// the whole requirement is reachable from `swift test` with nothing mocked.
@Suite("Installed detail projection")
struct InstalledDetailProjectionTests {

    // MARK: - II15 sc1 — detailed from the receipt alone

    @Test("A package the catalog does not carry is detailed from its receipt alone")
    func aReceiptOnlyPackageIsDetailedFromItsSnapshotAlone() throws {
        let homepage = try #require(URL(string: "https://acme.example/widget"))
        let snapshot = InstalledFixture.receipt(
            .formula,
            "widget",
            desc: "A widget for acme things",
            homepage: homepage,
            tap: "acme/tools",
            kegVersions: ["1.4.0"],
            linkedKeg: "1.4.0"
        )

        let detail = InstalledDetailProjection(snapshot)

        // Every value is the snapshot's own.
        #expect(detail.description == "A widget for acme things")
        #expect(detail.identity.map(\.label) == ["Type", "Homepage"])
        #expect(detail.identity.map(\.value) == ["Formula (CLI)", "https://acme.example/widget"])
        #expect(detail.identity.last?.style == .link(homepage))
        let tap = try #require(detail.tapOfOrigin)
        #expect(tap.label == "Tap")
        #expect(tap.value == "acme/tools")
        #expect(tap.style == .mono)
        #expect(detail.installStateFacts.map(\.label) == ["Version", "Link state"])
        #expect(detail.installStateFacts.map(\.value) == ["1.4.0", "Linked"])

        // …and the groups reach the consumer in the requirement's order.
        #expect(
            detail.orderedFacts.map(\.label)
                == ["Type", "Homepage", "Tap", "Version", "Link state"]
        )
    }

    @Test("The three groups keep their order and no label repeats")
    func theGroupsKeepTheirOrderAndNoLabelRepeats() throws {
        let homepage = try #require(URL(string: "https://acme.example/desk"))
        let formula = InstalledDetailProjection(InstalledFixture.receipt(
            .formula,
            "widget",
            homepage: homepage,
            kegVersions: ["1.0.0", "2.0.0"],
            linkedKeg: "2.0.0",
            isPinned: true,
            pinnedVersion: "2.0.0"
        ))
        let cask = InstalledDetailProjection(InstalledFixture.receipt(
            .cask,
            "desk",
            homepage: homepage,
            declaresAutoUpdates: true
        ))

        for detail in [formula, cask] {
            let labels = detail.orderedFacts.map(\.label)
            // The origin fact sits after every identity fact and before every
            // install-state fact — asserted on positions, not on a hand-built
            // concatenation the test could get right on its own.
            let tapIndex = try #require(labels.firstIndex(of: "Tap"))
            #expect(tapIndex == detail.identity.count)
            #expect(Array(labels.prefix(tapIndex)) == detail.identity.map(\.label))
            #expect(Array(labels.dropFirst(tapIndex + 1)) == detail.installStateFacts.map(\.label))
            #expect(Set(labels).count == labels.count, "a label appears twice: \(labels)")
        }

        // Triangulated on the shapes themselves: the two kinds really do emit
        // different install-state labels, so the loop above is not passing on
        // two identical inputs.
        #expect(formula.installStateFacts.map(\.label)
            == ["Version", "Link state", "Other versions", "Pin state"])
        #expect(cask.installStateFacts.map(\.label) == ["Updates"])
    }

    // MARK: - II15 sc3 — the kinds do not borrow each other's facts

    @Test("Facts do not cross between formula and cask")
    func factsDoNotCrossBetweenFormulaAndCask() throws {
        let formula = InstalledDetailProjection(InstalledFixture.receipt(
            .formula,
            "widget",
            kegVersions: ["1.0.0", "2.0.0"],
            linkedKeg: "2.0.0"
        ))
        let cask = InstalledDetailProjection(InstalledFixture.receipt(
            .cask,
            "desk",
            declaresAutoUpdates: false
        ))

        // Enumerated, not sampled: neither kind's whole fact list mentions the
        // other's vocabulary.
        let formulaText = formula.orderedFacts.map { $0.label + " " + $0.value }.joined(separator: "|")
        #expect(formulaText.contains("Updates") == false)
        #expect(formulaText.contains("Updated by Homebrew") == false)

        let caskText = cask.orderedFacts.map { $0.label + " " + $0.value }.joined(separator: "|")
        for absent in ["Version", "Link state", "Linked", "Other versions", "Pin state"] {
            #expect(caskText.contains(absent) == false, "a cask exposed \(absent)")
        }

        // …and it is unrepresentable rather than merely unwritten: the cask's
        // state has exactly one member and no place to put a keg (DD-2).
        guard case .cask(let caskState) = cask.kindState else {
            Issue.record("a cask projected a formula state")
            return
        }
        #expect(Mirror(reflecting: caskState).children.compactMap(\.label) == ["autoUpdates"])

        guard case .formula(let formulaState) = formula.kindState else {
            Issue.record("a formula projected a cask state")
            return
        }
        #expect(
            Mirror(reflecting: formulaState).children.compactMap(\.label)
                == ["primaryKegVersion", "linkState", "otherKegCount", "pin"]
        )
    }

    // MARK: - II15 sc4, II2 — three answers, not two

    @Test("A cask's auto-updates declaration has three distinguishable outcomes")
    func aCaskAutoUpdatesTriStateStaysThreeAnswers() {
        let declaredTrue = InstalledDetailProjection(
            InstalledFixture.receipt(.cask, "self-updater", declaresAutoUpdates: true)
        )
        let declaredFalse = InstalledDetailProjection(
            InstalledFixture.receipt(.cask, "brew-updated", declaresAutoUpdates: false)
        )
        let undeclared = InstalledDetailProjection(
            InstalledFixture.receipt(.cask, "silent", declaresAutoUpdates: nil)
        )

        #expect(declaredTrue.installStateFacts.map(\.value) == ["Updates itself"])
        #expect(declaredFalse.installStateFacts.map(\.value) == ["Updated by Homebrew"])
        #expect(undeclared.installStateFacts.isEmpty)
        #expect(undeclared.orderedFacts.contains { $0.label == "Updates" } == false)

        // Pairwise distinguishable, so "not declared" can never be read as
        // "declared false".
        #expect(declaredTrue.installStateFacts != declaredFalse.installStateFacts)
        #expect(declaredFalse.installStateFacts != undeclared.installStateFacts)
        #expect(declaredTrue.installStateFacts != undeclared.installStateFacts)
        #expect(declaredFalse.kindState != undeclared.kindState)
    }

    // MARK: - II15 sc5, sc6 — the primary keg survives both link states

    @Test("A linked multi-keg formula reports its primary keg and a count of the others")
    func aMultiKegFormulaShowsItsPrimaryKegAndACountOfTheRest() throws {
        let detail = InstalledDetailProjection(InstalledFixture.receipt(
            .formula,
            "widget",
            kegVersions: ["1.0.0", "1.5.0", "2.0.0"],
            linkedKeg: "1.5.0"
        ))

        #expect(detail.installStateFacts.map(\.label) == ["Version", "Link state", "Other versions"])
        #expect(
            detail.installStateFacts.map(\.value)
                == ["1.5.0", "Linked", "2 other versions installed"]
        )

        guard case .formula(let state) = detail.kindState else {
            Issue.record("a formula projected a cask state")
            return
        }
        // Nothing truncated the other kegs away: the count is the rest of them.
        #expect(state.primaryKegVersion == "1.5.0")
        #expect(state.otherKegCount == 2)
        #expect(state.linkState == .linked)
    }

    @Test("An unlinked formula still names its primary keg, and one other keg is singular")
    func anUnlinkedFormulaStillNamesItsPrimaryKeg() throws {
        let twoKegs = InstalledDetailProjection(InstalledFixture.receipt(
            .formula,
            "widget",
            kegVersions: ["1.0.0", "2.0.0"],
            linkedKeg: nil
        ))
        let oneKeg = InstalledDetailProjection(InstalledFixture.receipt(
            .formula,
            "gadget",
            kegVersions: ["3.1.4"],
            linkedKeg: nil
        ))

        // The version is not lost because no keg is linked.
        #expect(
            twoKegs.installStateFacts.map(\.value)
                == ["2.0.0", "Not linked", "1 other version installed"]
        )
        // …and a single-keg formula exposes no other-versions fact at all.
        #expect(oneKeg.installStateFacts.map(\.label) == ["Version", "Link state"])
        #expect(oneKeg.installStateFacts.map(\.value) == ["3.1.4", "Not linked"])
    }

    @Test("A formula reports both link states")
    func aFormulaReportsBothLinkStates() {
        let linked = InstalledDetailProjection(
            InstalledFixture.receipt(.formula, "widget", kegVersions: ["1.0.0"], linkedKeg: "1.0.0")
        )
        let unlinked = InstalledDetailProjection(
            InstalledFixture.receipt(.formula, "widget", kegVersions: ["1.0.0"], linkedKeg: nil)
        )

        #expect(linked.installStateFacts.map(\.value) == ["1.0.0", "Linked"])
        #expect(unlinked.installStateFacts.map(\.value) == ["1.0.0", "Not linked"])
    }

    @Test("A pinned formula reports its pin with and without a version")
    func aPinnedFormulaReportsItsPinWithAndWithoutAVersion() throws {
        let withVersion = InstalledDetailProjection(InstalledFixture.receipt(
            .formula,
            "widget",
            kegVersions: ["1.2.3"],
            linkedKeg: "1.2.3",
            isPinned: true,
            pinnedVersion: "1.2.3"
        ))
        let withoutVersion = InstalledDetailProjection(InstalledFixture.receipt(
            .formula,
            "widget",
            kegVersions: ["1.2.3"],
            linkedKeg: "1.2.3",
            isPinned: true,
            pinnedVersion: nil
        ))
        let notPinned = InstalledDetailProjection(InstalledFixture.receipt(
            .formula,
            "widget",
            kegVersions: ["1.2.3"],
            linkedKeg: "1.2.3"
        ))

        #expect(withVersion.installStateFacts.last?.value == "Pinned at 1.2.3")
        #expect(withoutVersion.installStateFacts.last?.value == "Pinned")
        #expect(notPinned.installStateFacts.contains { $0.label == "Pin state" } == false)

        // Three states, all distinguishable on the value itself.
        let pins = try [withVersion, withoutVersion, notPinned].map { detail -> InstalledDetailProjection.FormulaState.Pin in
            guard case .formula(let state) = detail.kindState else {
                throw PinUnavailable()
            }
            return state.pin
        }
        #expect(pins == [.pinned(version: "1.2.3"), .pinned(version: nil), .notPinned])
    }

    private struct PinUnavailable: Error {}

    // MARK: - II15 sc7, PD8, PT3 — a withheld tap is absent, not empty

    @Test("A withheld tap yields no origin fact")
    func aWithheldTapProducesNoOriginFact() {
        let withheld = InstalledDetailProjection(
            InstalledFixture.receipt(.formula, "widget", tap: nil)
        )
        let reported = InstalledDetailProjection(
            InstalledFixture.receipt(.formula, "widget", tap: "acme/tools")
        )

        #expect(withheld.tapOfOrigin == nil)
        #expect(withheld.orderedFacts.contains { $0.label == "Tap" } == false)
        // No placeholder and no explanatory note: the whole fact is gone, and
        // the rest of the detail is untouched by its absence.
        #expect(withheld.orderedFacts.count == reported.orderedFacts.count - 1)
        #expect(withheld.installStateFacts == reported.installStateFacts)
        #expect(withheld.identity == reported.identity)

        // Triangulated: the same shape *with* a tap does produce the fact, so
        // the absence above is the tap's doing and not the fixture's.
        #expect(reported.tapOfOrigin?.value == "acme/tools")
    }

    // MARK: - II15 sc8, DD-3 — absence is omission, never a sentinel

    @Test("An absent description or homepage is absent, not empty")
    func absentDescriptionAndHomepageAreOmittedNotEmptied() throws {
        let bare = InstalledDetailProjection(
            InstalledFixture.receipt(.formula, "widget", desc: nil, homepage: nil)
        )
        let published = InstalledDetailProjection(InstalledFixture.receipt(
            .formula,
            "widget",
            desc: "A widget for acme things",
            homepage: try #require(URL(string: "https://acme.example/widget"))
        ))

        #expect(bare.description == nil)
        #expect(bare.identity.map(\.label) == ["Type"])
        #expect(published.identity.map(\.label) == ["Type", "Homepage"])

        // The absence set is enumerated across every shape this suite builds,
        // not sampled: no emitted value is ever empty or a stand-in for absence.
        let everyShape = [
            bare,
            published,
            InstalledDetailProjection(InstalledFixture.receipt(.formula, "widget", tap: nil)),
            InstalledDetailProjection(InstalledFixture.receipt(
                .formula,
                "widget",
                kegVersions: ["1.0.0", "2.0.0"],
                linkedKeg: nil,
                isPinned: true,
                pinnedVersion: nil
            )),
            InstalledDetailProjection(
                InstalledFixture.receipt(.cask, "desk", declaresAutoUpdates: true)
            ),
            InstalledDetailProjection(
                InstalledFixture.receipt(.cask, "desk", declaresAutoUpdates: false)
            ),
            InstalledDetailProjection(
                InstalledFixture.receipt(.cask, "desk", declaresAutoUpdates: nil)
            )
        ]
        let emitted = everyShape.flatMap(\.orderedFacts)
        #expect(emitted.isEmpty == false, "the enumeration below would prove nothing on no facts")
        for fact in emitted {
            #expect(fact.value.isEmpty == false, "\(fact.label) emitted an empty value")
            #expect(fact.label.isEmpty == false)
            for sentinel in ["unknown", "Unknown", "—", "-", "n/a", "N/A"] {
                #expect(fact.value != sentinel, "\(fact.label) emitted the sentinel \(sentinel)")
            }
        }
        #expect(everyShape.compactMap(\.description).allSatisfy { $0.isEmpty == false })
    }
}
