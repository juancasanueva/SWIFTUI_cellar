import Catalog
import Foundation
import Testing

@testable import BrewClient

/// The name-only detail a **not-installed** tap package resolves to
/// (`package-search` PS8 round 6, `package-detail` PD6, `tap-management` TM5).
///
/// Every claim here is about a pure projection over two already-resident
/// inventories, so none of it needs a view, a store or a process. The two
/// interesting properties are the **exactly-one-publisher** rule — a detail that
/// guessed a tap would name the wrong origin — and the **absence set**: what the
/// value cannot carry, because the tap inventory publishes none of it and
/// fetching any of it would need the tap-source read TM5 forbids
/// unconditionally.
@Suite("Tap inventory detail", .timeLimit(.minutes(1)))
struct TapInventoryDetailTests {

    private static let widget = PackageID(kind: .formula, name: "widget")

    private func resolve(
        _ id: PackageID = TapInventoryDetailTests.widget,
        taps: [TapRecord],
        installed: InstalledInventory = .empty
    ) -> TapInventoryDetail? {
        TapInventoryDetail.resolve(
            id,
            in: TapSearchFixture.inventory(taps),
            installed: installed
        )
    }

    // MARK: - PS8 round 6 — exactly one publisher, and its four names

    @Test("One tap publishing the identity resolves to its four names")
    func oneTapPublishingTheIdentityResolvesToItsFourNames() throws {
        let detail = try #require(
            resolve(taps: [TapSearchFixture.tap("acme/tools", formulae: ["acme/tools/widget"])])
        )

        // The bare token brew installs by, the kind, and the tap of origin —
        // the three things the inventory published — plus the one sentence
        // about this Mac.
        #expect(detail.id == Self.widget)
        #expect(detail.displayName == "widget")
        #expect(detail.kind == .formula)
        #expect(detail.tapName == "acme/tools")
        // TM5's exact shipped string, reused byte-for-byte rather than reworded
        // (PS8's pinned copy table).
        #expect(detail.stateCopy == "Not installed.")
        #expect(detail.footerCopy == "Cellar knows this package by name only until it is installed.")

        // The enumeration is the absence proof: `Mirror` sees stored properties,
        // so a fact the type carries and this list omits cannot exist. `kind`
        // is deliberately absent from it — it answers off `id`, which is
        // enumerated, and a second stored copy of one fact is the drift PS8's
        // one-projection rule forbids.
        let labels = Mirror(reflecting: detail).children.compactMap(\.label).sorted()
        #expect(labels == ["displayName", "footerCopy", "id", "stateCopy", "tapName"])
        for absent in [
            "desc", "description", "version", "homepage", "license", "dependencies",
            "dependents", "installcount", "deprecated", "disabled", "size", "caveats",
            "analytics", "collision", "trust", "grant"
        ] {
            #expect(
                labels.contains { $0.lowercased().contains(absent) } == false,
                "the name-only detail exposes \(absent)"
            )
        }
        // …and no emitted string stands in for an absence.
        for child in Mirror(reflecting: detail).children {
            guard let text = child.value as? String else { continue }
            #expect(text.isEmpty == false)
            #expect(text != "-")
            #expect(text.lowercased() != "unknown")
        }
    }

    /// A cask resolves on exactly the same rule, through the same fully
    /// qualified token brew publishes it under — the kind is part of the
    /// identity, so a formula of the same name is a different package (TM5).
    @Test("A cask published by one tap resolves to its own identity")
    func aCaskPublishedByOneTapResolvesToItsOwnIdentity() throws {
        let desk = PackageID(kind: .cask, name: "desk")
        let taps = [TapSearchFixture.tap("bravo/tools", casks: ["bravo/tools/desk"])]

        let detail = try #require(resolve(desk, taps: taps))
        #expect(detail.kind == .cask)
        #expect(detail.displayName == "desk")
        #expect(detail.tapName == "bravo/tools")
        // The same bare token as a **formula** is a different identity, and that
        // tap publishes no such thing.
        #expect(resolve(PackageID(kind: .formula, name: "desk"), taps: taps) == nil)
    }

    // MARK: - PS8 round 6 — zero publishers, several, and an official one

    @Test("An unpublished or doubly published identity resolves to nothing")
    func anUnpublishedOrDoublyPublishedIdentityResolvesToNothing() throws {
        let acme = TapSearchFixture.tap("acme/tools", formulae: ["acme/tools/widget"])
        let bravo = TapSearchFixture.tap("bravo/tools", formulae: ["bravo/tools/widget"])

        // Nothing publishes it.
        #expect(resolve(taps: [TapSearchFixture.tap("carol/tools", formulae: ["carol/tools/other"])]) == nil)
        // Two taps publish it: there is no single tap of origin to name, so no
        // detail may claim one.
        #expect(resolve(taps: [acme, bravo]) == nil)
        // Only an **official** tap publishes it. The catalog owns that package,
        // and this projection reads third-party taps alone.
        #expect(resolve(taps: [TapSearchFixture.tap("homebrew/core", formulae: ["widget"])]) == nil)
        // Triangulated: with exactly one of the two third-party taps present,
        // the same identity does resolve — so the `nil`s above are the rule
        // working, not an inventory that answered nothing.
        let resolved = try #require(resolve(taps: [acme]))
        #expect(resolved.tapName == "acme/tools")
        // …and the official tap alongside it changes nothing.
        let withOfficial = try #require(
            resolve(taps: [acme, TapSearchFixture.tap("homebrew/core", formulae: ["widget"])])
        )
        #expect(withOfficial.tapName == "acme/tools")
    }

    // MARK: - PS8 round 6 — a package with a receipt belongs to the receipt route

    /// The guard that keeps `stateCopy` honest.
    ///
    /// It asks the **same** question the receipt-backed branch asks — does this
    /// machine hold a record for this exact identity — so the two branches can
    /// never both answer, and this one can never say “Not installed.” about a
    /// package that is installed.
    @Test("An identity this machine has a receipt for resolves to nothing here")
    func anIdentityWithAReceiptResolvesToNothingHere() throws {
        let acme = TapSearchFixture.tap("acme/tools", formulae: ["acme/tools/widget"])

        #expect(
            resolve(taps: [acme], installed: TapSearchFixture.acmeWidgetInstalled) == nil,
            "an installed package reached the name-only detail instead of its receipt"
        )
        // The withheld case, which is the one an install-state test would miss:
        // Homebrew withholds the tap, so the receipt's `tap` is absent — but the
        // receipt exists, and it is the receipt that decides.
        let withheldTap = TapSearchFixture.tap(
            "acme/tools",
            formulae: ["acme/tools/widget"],
            trust: .untrusted
        )
        #expect(TapSearchFixture.withheldWidgetInstalled.package(Self.widget)?.tap == nil)
        #expect(resolve(taps: [withheldTap], installed: TapSearchFixture.withheldWidgetInstalled) == nil)

        // Triangulated on the receipt alone: same taps, same identity, empty
        // installed inventory, and the detail comes back.
        let absent = try #require(resolve(taps: [acme], installed: .empty))
        #expect(absent.stateCopy == "Not installed.")
        // A receipt for a **different** identity does not withhold this one.
        let other = InstalledInventory(packages: [
            InstalledFixture.receipt(.formula, "other", tap: "acme/tools")
        ])
        #expect(try #require(resolve(taps: [acme], installed: other)).id == Self.widget)
    }

    // MARK: - PD6 / TM5 — nothing enters the catalog and nothing is read

    @Test("The name-only detail reaches no catalog value and no tap source")
    func theNameOnlyDetailReachesNoCatalogValueAndNoTapSource() throws {
        let acme = TapSearchFixture.tap("acme/tools", formulae: ["acme/tools/widget"])
        let index = TapSearchFixture.index([
            TapSearchFixture.catalogPackage(.formula, "wget", desc: "retrieve files")
        ])
        let before = index.search("widget")

        let detail = try #require(resolve(taps: [acme]))
        #expect(detail.tapName == "acme/tools")

        // The catalog is unchanged, still carries no record for the package, and
        // the composition consulted none of it: the projection's whole input is
        // the two resident inventories.
        #expect(index.package(Self.widget) == nil)
        #expect(index.search("widget") == before)
        #expect(before.isEmpty)

        // The source itself names no process layer and no catalog record type —
        // the structural half of the same claim, in the shipped source-scan
        // idiom. `PackageID` and `PackageKind` are identity, not catalog values,
        // and stay permitted.
        let source = try Self.source(of: "Sources/BrewClient/TapInventoryDetail.swift")
        #expect(
            source.contains("public struct TapInventoryDetail"),
            "the scan read a file that is not the resolution"
        )
        for forbidden in [
            "Process", "BrewProcess", "CatalogStore", "CatalogPackage", "CatalogSnapshot",
            "PackageSearchIndex", "await", "Task("
        ] {
            #expect(
                source.contains(forbidden) == false,
                "the resolution reaches \(forbidden)"
            )
        }
    }

    /// Package-rooted, so the scan cannot silently read an empty string — the
    /// gotcha `SnoozeGuardTests` records at length.
    private static func source(of relative: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // BrewClientTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // CellarCore
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relative),
            encoding: .utf8
        )
    }
}
