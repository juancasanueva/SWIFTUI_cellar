import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// `package-trust` PT4 :219-244 — every decoded entry lands in exactly one
/// accounted category, and the categories add up to what brew sent.
///
/// The five categories are the corrected shape: attributed · excluded tap grants
/// · orphan tap grants · unmatched package grants · other. A three-category
/// value cannot express the partition, because an orphan tap grant is neither a
/// package grant nor a grant Cellar may quietly discard.
@Suite("Per-package trust accounting")
struct TrustGrantAccountingTests {
    private static let acme = TapRecord(
        name: "acme/tools",
        repository: "tools",
        caskTokens: ["acme/tools/widget"]
    )
    private static let other = TapRecord(
        name: "other/tools",
        repository: "tools",
        caskTokens: ["other/tools/desk"]
    )

    // MARK: - PT4 :246-252 — the accounting partitions the decoded set

    @Test("The accounting partitions the decoded set")
    func theAccountingPartitionsTheDecodedSet() {
        let ledger = TrustGrantLedger(
            formulae: ["https://github.com/cloudmanic/spice-edit/spice-edit"],
            casks: ["acme/tools/widget", "other/tools/desk", "nobody/tools/lost"],
            taps: ["acme/tools", "ghost/tools"],
            commands: ["acme/tools/thing"]
        )
        let taps = [Self.acme, Self.other]
        let accounting = TapProjection.accounting(of: ledger, taps: taps)

        // The exact totals PT4's fixture pins.
        #expect(ledger.entryCount == 7)
        #expect(accounting.attributed == 2)
        #expect(accounting.excluded == 1)
        #expect(accounting.orphanTapGrants == ["ghost/tools"])
        #expect(accounting.unmatchedFormulae == ["https://github.com/cloudmanic/spice-edit/spice-edit"])
        #expect(accounting.unmatchedCasks == ["nobody/tools/lost"])
        #expect(accounting.unmatchedCount == 2)
        #expect(accounting.other == ["acme/tools/thing"])

        // They partition: the totals sum to the entries decoded, and every entry
        // appears in exactly one category.
        #expect(accounting.total == ledger.entryCount)
        let surfaced = accounting.orphanTapGrants + accounting.unmatchedFormulae
            + accounting.unmatchedCasks + accounting.other
        #expect(Set(surfaced).count == surfaced.count, "an entry landed in two categories")
        #expect(accounting.attributed + accounting.excluded + surfaced.count == 7)

        // …and no `taps` entry contributes to any package count: removing that
        // namespace changes neither tap's projection.
        let withoutTaps = TrustGrantLedger(
            formulae: ledger.formulae,
            casks: ledger.casks,
            commands: ledger.commands
        )
        for tap in taps {
            #expect(
                TapProjection.grants(for: tap, in: .reported(ledger))
                    == TapProjection.grants(for: tap, in: .reported(withoutTaps)),
                "\(tap.name)'s count moved with the ledger's taps namespace"
            )
        }
        #expect(TapProjection.grants(for: Self.acme, in: .reported(ledger)).countLine
            == "1 trusted individually")
    }

    // MARK: - PT4 :254-260 — the namespaces are not disjoint

    /// Measured, not supposed: `gentleman-programming/tap/engram` really is in
    /// both `formulae` and `casks` on a real Mac (Engram `#7764`). Two entries
    /// about two different packages that happen to share an identifier.
    @Test("The same identifier in two namespaces is two entries")
    func theSameIdentifierInTwoNamespacesIsTwoEntries() async throws {
        let ledger = try await TrustGrantDecoder.decode(TrustGrantFixture.measuredPayload)
        let gentleman = TapRecord(
            name: "gentleman-programming/tap",
            repository: "tap",
            formulaNames: ["gentleman-programming/tap/engram"],
            caskTokens: ["gentleman-programming/tap/engram"]
        )
        let guria = TapRecord(
            name: "guria/tap",
            repository: "tap",
            caskTokens: ["guria/tap/nehir", "guria/tap/nehir@rc"]
        )
        let report = TrustGrantState.reported(ledger)

        // Both occurrences decoded, and both accounted — separately.
        #expect(ledger.formulae.filter { $0 == "gentleman-programming/tap/engram" }.count == 1)
        #expect(ledger.casks.filter { $0 == "gentleman-programming/tap/engram" }.count == 1)
        let presentation = TapProjection.grants(for: gentleman, in: report)
        #expect(presentation.marked == [
            PackageID(kind: .formula, name: "engram"),
            PackageID(kind: .cask, name: "engram")
        ])
        #expect(presentation.countLine == "2 trusted individually", "one occurrence masked the other")

        // Neither deduplicates, displaces, overwrites or masks the other.
        let accounting = TapProjection.accounting(of: ledger, taps: [gentleman, guria])
        #expect(accounting.total == ledger.entryCount)
        #expect(accounting.attributed == 4, "the shared identifier was counted once")

        // A grant for one kind does not mark the other kind. Triangulated on a
        // ledger that lists the identifier in **one** namespace only.
        let formulaOnly = TrustGrantState.reported(
            TrustGrantLedger(formulae: ["gentleman-programming/tap/engram"])
        )
        #expect(TapProjection.grantsIndividually(
            PackageID(kind: .formula, name: "engram"),
            publishedBy: "gentleman-programming/tap",
            in: formulaOnly
        ))
        #expect(TapProjection.grantsIndividually(
            PackageID(kind: .cask, name: "engram"),
            publishedBy: "gentleman-programming/tap",
            in: formulaOnly
        ) == false)

        // …and `@` neither truncates the name nor fails the attribution.
        let nehir = TapProjection.grants(for: guria, in: report)
        #expect(nehir.marked == [
            PackageID(kind: .cask, name: "nehir"),
            PackageID(kind: .cask, name: "nehir@rc")
        ])
        #expect(nehir.countLine == "2 trusted individually")
    }

    // MARK: - PT4 :262-268 — the commands namespace is counted, never dropped

    @Test("The commands namespace is counted, never dropped")
    func theCommandsNamespaceIsCountedNeverDropped() {
        // A report whose only entries are in `commands`.
        let commandsOnly = TrustGrantLedger(commands: ["acme/tools/thing", "other/tools/tool"])
        let accounting = TapProjection.accounting(of: commandsOnly, taps: [Self.acme])
        let section = TapProjection.unattributedSection(
            in: .reported(commandsOnly),
            taps: [Self.acme]
        )

        #expect(accounting.other == ["acme/tools/thing", "other/tools/tool"])
        #expect(accounting.total == 2)
        #expect(section.groups.isEmpty == false, "the section rendered nothing for a real report")
        #expect(section.groups.flatMap(\.entries) == ["acme/tools/thing", "other/tools/tool"])
        #expect(section != .noneRecorded)

        // A present-and-empty `commands` beside populated namespaces: a report
        // of nothing in that namespace, distinguishable from a payload with no
        // `commands` key at all.
        let declared = TrustGrantLedger(
            casks: ["acme/tools/widget"],
            commands: [],
            declaredNamespaces: ["casks", "commands"]
        )
        let undeclared = TrustGrantLedger(casks: ["acme/tools/widget"])
        #expect(declared.declaresCommands)
        #expect(undeclared.declaresCommands == false)
        #expect(declared != undeclared)

        // …and neither report is presented as empty.
        for ledger in [declared, undeclared] {
            let presented = TapProjection.unattributedSection(
                in: .reported(ledger),
                taps: [Self.acme]
            )
            #expect(presented != .noneRecorded, "a populated report was presented as empty")
            #expect(TapProjection.grants(for: Self.acme, in: .reported(ledger)).countLine
                == "1 trusted individually")
        }

        // An unmodelled namespace lands in the same "other" bucket rather than
        // vanishing between the decode and the accounting.
        let unmodelled = TrustGrantLedger(unmodelled: ["plugins": ["acme/tools/plug"]])
        let plugged = TapProjection.accounting(of: unmodelled, taps: [Self.acme])
        #expect(plugged.other == ["acme/tools/plug"])
        #expect(plugged.total == 1)
    }
}
