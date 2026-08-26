import Catalog
import Foundation
import Testing

@testable import BrewClient

/// The value the menu bar reads, and the one thing it must never do: derive
/// outdated-ness for itself (menu-bar "The menu-bar projection is a pure value
/// that delegates outdated-ness rather than recomputing it").
///
/// Every assertion here pairs the projection's answer with the answer
/// `InstalledBrowse` gives for the same inputs. A reimplementation that happened
/// to agree today would still be wrong, because the next rule added to the
/// projection would pass it by — so the rows below compare against the delegate
/// rather than against a literal wherever the delegate has an opinion.
@Suite("Menu-bar projection")
struct MenuBarProjectionTests {
    private static let alpha = PackageID(kind: .formula, name: "alpha")
    private static let bravo = PackageID(kind: .formula, name: "bravo")
    private static let charlie = PackageID(kind: .formula, name: "charlie")
    private static let delta = PackageID(kind: .formula, name: "delta")

    /// The version every outdated fixture package is offered at, so a snooze can
    /// be taken against exactly the value the record publishes.
    private static let offered = "2.0.0"

    /// The repository root, reached from this file rather than from a working
    /// directory the test runner does not promise (the `SnoozeGuardTests`
    /// idiom).
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // BrewClientTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // CellarCore
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // the repository

    private static func ids(_ count: Int) -> [PackageID] {
        (1...count).map { PackageID(kind: .formula, name: String(format: "pkg-%02d", $0)) }
    }

    private static func outdatedInventory(_ count: Int) -> InstalledInventory {
        InstalledFixture.inventory(
            outdated: Dictionary(uniqueKeysWithValues: ids(count).map { ($0, offered) })
        )
    }

    private static func browse(_ inventory: InstalledInventory) -> InstalledBrowse {
        InstalledBrowse(inventory: inventory, isAvailable: true)
    }

    // MARK: - T1 — the count and the set are the delegate's, not this value's

    @Test("The projection counts and sets exactly what the browse does")
    func theProjectionCountsAndSetsExactlyWhatTheBrowseDoes() {
        // A snoozed formula, an outdated self-updating cask, and three other
        // outdated packages: two independent exclusions, neither of them stated
        // here.
        let cask = InstalledFixture.receipt(
            .cask,
            "zulu-desktop",
            outdatedTo: Self.offered,
            declaresAutoUpdates: true
        )
        let outdated = [Self.alpha, Self.bravo, Self.charlie, Self.delta].map {
            InstalledFixture.package($0, catalogVersion: Self.offered)
        }
        let browse = Self.browse(InstalledInventory(packages: outdated + [cask]))
        let snapshot: MetadataSnapshot = [Self.alpha: PackageMetadata(snoozedVersion: Self.offered)]

        let projection = MenuBarProjection(
            browse: browse,
            metadata: snapshot.lookup,
            services: []
        )

        #expect(projection.outdatedCount == 3)
        #expect(projection.outdatedIDs == [Self.bravo, Self.charlie, Self.delta])
        // Set equality against the delegate, not a subset of it.
        #expect(projection.outdatedIDs == browse.outdatedIDs(metadata: snapshot.lookup))
        #expect(projection.outdatedCount == browse.outdatedCount(metadata: snapshot.lookup))
        // A surface presenting both states one consistent fact.
        #expect(projection.outdatedCount == projection.outdatedIDs.count)
        // The self-updating cask is absent, and no auto-update rule was stated
        // here to make it so.
        #expect(projection.outdatedIDs.contains(cask.id) == false)
        #expect(projection.topOutdated.map(\.id) == [Self.bravo, Self.charlie, Self.delta])

        // Triangulated with no metadata at all: both fall back to the
        // inventory's own set, and the snoozed package returns.
        let cold = MenuBarProjection(browse: browse, metadata: nil, services: [])
        #expect(cold.outdatedIDs == browse.outdatedIDs(metadata: nil))
        #expect(cold.outdatedIDs == [Self.alpha, Self.bravo, Self.charlie, Self.delta])
        #expect(cold.outdatedCount == 4)
    }

    // MARK: - T2 — a snooze is absent from the count, the set and the entries

    @Test("A snoozed package is in neither the count, the set, nor the entries")
    func aSnoozedPackageIsInNeitherTheCountTheSetNorTheEntries() throws {
        let inventory = Self.outdatedInventory(7)
        let browse = Self.browse(inventory)
        let first = try #require(inventory.packages.first)
        let snapshot: MetadataSnapshot = [first.id: PackageMetadata(snoozedVersion: Self.offered)]

        let projection = MenuBarProjection(
            browse: browse,
            metadata: snapshot.lookup,
            services: []
        )

        #expect(projection.outdatedCount == 6)
        #expect(projection.outdatedIDs.contains(first.id) == false)
        #expect(projection.topOutdated.count == 5)
        #expect(projection.topOutdated.contains { $0.id == first.id } == false)
        // Entries plus remainder equals the announced count exactly.
        #expect(projection.remainingOutdatedCount == 1)
        #expect(projection.topOutdated.count + (projection.remainingOutdatedCount ?? 0) == 6)
        #expect(projection.andMoreLabel == "and 1 more")

        // The naive filter this projection exists to replace is strictly
        // greater, so the row fails the moment the projection reverts to it.
        let naive = inventory.packages.filter(\.isOutdated).count
        #expect(naive == 7)
        #expect(naive > projection.outdatedCount)
    }

    // MARK: - T3 — the remainder and the title are absences, never zeroes

    @Test("The remainder and the title are absences, not zeroes")
    func theRemainderAndTheTitleAreAbsencesNotZeroes() {
        let twelve = MenuBarProjection(
            browse: Self.browse(Self.outdatedInventory(12)),
            metadata: nil,
            services: []
        )
        #expect(twelve.topOutdated.count == 5)
        #expect(twelve.topOutdated.map(\.name) == ["pkg-01", "pkg-02", "pkg-03", "pkg-04", "pkg-05"])
        #expect(twelve.remainingOutdatedCount == 7)
        #expect(twelve.andMoreLabel == "and 7 more")
        #expect(twelve.statusItemTitle == "12")

        // The singular, which a remainder of exactly one reaches in practice.
        let six = MenuBarProjection(
            browse: Self.browse(Self.outdatedInventory(6)),
            metadata: nil,
            services: []
        )
        #expect(six.remainingOutdatedCount == 1)
        #expect(six.andMoreLabel == "and 1 more")

        // At and below the limit the remainder is absent, and absence is not a
        // zero and not an empty string.
        for count in [5, 4] {
            let projection = MenuBarProjection(
                browse: Self.browse(Self.outdatedInventory(count)),
                metadata: nil,
                services: []
            )
            #expect(projection.topOutdated.count == count)
            #expect(projection.remainingOutdatedCount == nil)
            #expect(projection.andMoreLabel == nil)
            #expect(projection.andMoreLabel != "")
        }

        let three = MenuBarProjection(
            browse: Self.browse(Self.outdatedInventory(3)),
            metadata: nil,
            services: []
        )
        #expect(three.statusItemTitle == "3")

        // Zero: the absence *is* the value.
        let zero = MenuBarProjection(
            browse: Self.browse(InstalledFixture.inventory(upToDate: Self.ids(4))),
            metadata: nil,
            services: []
        )
        #expect(zero.outdatedCount == 0)
        #expect(zero.statusItemTitle == nil)
        #expect(zero.statusItemTitle != "0")
        #expect(zero.statusItemTitle != "")
        #expect(zero.topOutdated.isEmpty)
        #expect(zero.remainingOutdatedCount == nil)
        #expect(zero.andMoreLabel == nil)

        // An empty inventory and an unavailable one are the same ordinary zero,
        // and neither is distinguishable from a healthy inventory with nothing
        // outdated.
        let empty = MenuBarProjection(
            browse: InstalledBrowse(inventory: .empty, isAvailable: true),
            metadata: nil,
            services: []
        )
        let unavailable = MenuBarProjection(
            browse: InstalledBrowse(inventory: .empty, isAvailable: false),
            metadata: nil,
            services: []
        )
        #expect(empty.outdatedCount == 0)
        #expect(unavailable.outdatedCount == 0)
        #expect(empty == unavailable)
        #expect(empty == zero)
    }

    // MARK: - T19 — nothing effectful to inject, and equal composed twice

    @Test("The projection has no effectful dependency and is equal composed twice")
    func theProjectionHasNoEffectfulDependencyAndIsEqualComposedTwice() throws {
        let inventory = Self.outdatedInventory(3)
        let browse = Self.browse(inventory)
        let services = [ServiceRecord(name: "postgresql", status: .started)]

        let first = MenuBarProjection(browse: browse, metadata: nil, services: services)
        let second = MenuBarProjection(browse: browse, metadata: nil, services: services)
        #expect(first == second)

        // Not vacuous: one snooze over the same inventory makes them differ.
        let snoozedID = try #require(inventory.packages.first).id
        let snapshot: MetadataSnapshot = [snoozedID: PackageMetadata(snoozedVersion: Self.offered)]
        let snoozed = MenuBarProjection(browse: browse, metadata: snapshot.lookup, services: services)
        #expect(first != snoozed)

        // The stored facts are the declared ones, and none of them is a store,
        // a launcher, a session or a clock.
        let labels = Mirror(reflecting: first).children.compactMap(\.label)
        #expect(
            Set(labels) == ["outdatedCount", "outdatedIDs", "topOutdated", "services", "runningServiceCount"],
            "the projection stores \(labels)"
        )
        let effectful = ["Store", "Coordinator", "Launch", "URLSession", "Clock", "Process"]
        for child in Mirror(reflecting: first).children {
            let type = String(describing: type(of: child.value))
            for token in effectful {
                #expect(type.contains(token) == false, "\(child.label ?? "?") is a \(type)")
            }
        }

        // And there is nothing of that kind to inject: the initializer takes
        // three values and no seam.
        let source = try String(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("Packages/CellarCore/Sources/BrewClient/MenuBarProjection.swift"),
            encoding: .utf8
        )
        #expect(source.contains("public struct MenuBarProjection"), "the projection source was not read")

        var signatures: [String] = []
        var cursor = source.startIndex
        while let start = source.range(of: "public init(", range: cursor..<source.endIndex) {
            let end = try #require(source.range(of: ")", range: start.upperBound..<source.endIndex))
            signatures.append(String(source[start.upperBound..<end.lowerBound]))
            cursor = end.upperBound
        }
        // Anchored: every initializer this file declares was read, and one of
        // them is the projection's own.
        #expect(signatures.count == 2, "read \(signatures.count) initializers: \(signatures)")
        #expect(signatures.contains { $0.contains("browse") }, "the projection's initializer was not read")
        for signature in signatures {
            for token in effectful {
                #expect(signature.contains(token) == false, "an initializer takes a \(token): \(signature)")
            }
        }
    }
}
