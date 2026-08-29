import Catalog
import Foundation
import Testing

@testable import BrewClient

/// The projection from npm's two documents into the one inventory type.
///
/// The freshness state is what decides whether an npm row may claim to be
/// behind. `notChecked` and `failed` produce rows that are *present and current*
/// rather than rows that are absent: the packages are installed either way, and
/// hiding them because the registry was unreachable would be a second wrong
/// answer on top of the first.
@Suite("npm inventory projection")
struct NpmProjectionTests {
    private static let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static func inventory(_ outdated: NpmOutdatedState) -> NpmInventory {
        NpmInventory(
            packages: [
                NpmGlobalPackage(name: "typescript", version: "5.6.2"),
                NpmGlobalPackage(name: "@angular/cli", version: "18.2.0"),
            ],
            outdated: outdated
        )
    }

    private static let fresh = NpmOutdatedState.fresh(
        [
            "typescript": NpmOutdatedRecord(current: "5.6.2", wanted: "5.6.2", latest: "5.7.0"),
            "@angular/cli": NpmOutdatedRecord(
                current: "18.2.0", wanted: "18.2.0", latest: "18.2.0"
            ),
        ],
        at: checkedAt
    )

    @Test("Every global becomes one installed package under the npm identity")
    func globalsBecomeInstalledPackages() {
        let packages = Self.inventory(Self.fresh).installedPackages()

        // A mapping, so it preserves the listing's order. Ordering the rows is
        // `InstalledInventory`'s job — it has to interleave two sources anyway,
        // so sorting here would be a second, weaker ordering that only ever
        // agrees by coincidence.
        #expect(packages.map(\.id) == [
            PackageID(kind: .npm, name: "typescript"),
            PackageID(kind: .npm, name: "@angular/cli"),
        ])
        #expect(packages.allSatisfy { $0.kind == .npm })
        #expect(InstalledInventory(packages: packages).packages.map(\.name)
            == ["@angular/cli", "typescript"])
    }

    @Test("Each row has exactly one keg, installed on request, with no timestamp")
    func rowsHaveOneOnRequestKeg() throws {
        let typescript = try #require(
            Self.inventory(Self.fresh).installedPackages().first { $0.name == "typescript" }
        )

        #expect(typescript.kegs.count == 1)
        #expect(typescript.primaryKeg.version == "5.6.2")
        #expect(typescript.installedVersion == "5.6.2")
        #expect(typescript.primaryKeg.installedOnRequest)
        #expect(typescript.isOnRequest)
        // npm's listing carries no install date, and the epoch is not a date
        // this machine can be said to have installed anything on.
        #expect(typescript.installedAt == nil)
    }

    @Test("Members that belong to Homebrew's payload are absent, not defaulted")
    func homebrewOnlyMembersAreAbsent() throws {
        let typescript = try #require(
            Self.inventory(Self.fresh).installedPackages().first { $0.name == "typescript" }
        )

        #expect(typescript.tap == nil)
        #expect(typescript.linkedKeg == nil)
        #expect(typescript.declaresAutoUpdates == nil)
        #expect(typescript.isSelfUpdating == false)
        #expect(typescript.isPinned == false)
        #expect(typescript.pinnedVersion == nil)
        #expect(typescript.displayName == "typescript")
    }

    @Test("A fresh check offers latest and marks only the package that is behind")
    func freshCheckMarksTheOutdatedOne() throws {
        let packages = Self.inventory(Self.fresh).installedPackages()
        let typescript = try #require(packages.first { $0.name == "typescript" })
        let angular = try #require(packages.first { $0.name == "@angular/cli" })

        #expect(typescript.catalogVersion == "5.7.0")
        #expect(typescript.snapshotOutdated)
        #expect(typescript.isOutdated)

        #expect(angular.catalogVersion == "18.2.0")
        #expect(angular.snapshotOutdated == false)
        #expect(angular.isOutdated == false)
    }

    @Test("An unchecked source offers no version and marks nothing outdated")
    func notCheckedOffersNothing() throws {
        let packages = Self.inventory(.notChecked(.notYetChecked)).installedPackages()
        let typescript = try #require(packages.first { $0.name == "typescript" })

        #expect(packages.count == 2)
        // The installed version, not an invented one: with no check there is no
        // offered version, and `catalogVersion` must not imply otherwise.
        #expect(typescript.catalogVersion == "5.6.2")
        #expect(typescript.snapshotOutdated == false)
        #expect(typescript.isOutdated == false)
    }

    @Test("A failed check keeps every package and marks none outdated")
    func failedCheckKeepsPackages() throws {
        let packages = Self.inventory(.failed(.networkUnavailable)).installedPackages()
        let typescript = try #require(packages.first { $0.name == "typescript" })

        #expect(packages.count == 2)
        #expect(typescript.catalogVersion == "5.6.2")
        #expect(typescript.isOutdated == false)
    }

    @Test("A fresh report about a package that is no longer installed adds no row")
    func staleReportEntriesDoNotResurrectPackages() {
        let inventory = NpmInventory(
            packages: [NpmGlobalPackage(name: "typescript", version: "5.6.2")],
            outdated: .fresh(
                [
                    "typescript": NpmOutdatedRecord(
                        current: "5.6.2", wanted: "5.6.2", latest: "5.7.0"
                    ),
                    "corepack": NpmOutdatedRecord(
                        current: "0.29.4", wanted: "0.31.0", latest: "0.31.0"
                    ),
                ],
                at: Self.checkedAt
            )
        )

        let packages = inventory.installedPackages()

        #expect(packages.map(\.name) == ["typescript"])
    }

    @Test("A report whose current disagrees with the listing trusts the listing")
    func listingWinsOnTheInstalledVersion() throws {
        // `ls` and `outdated` are two separate invocations; a package upgraded
        // between them makes the report's `current` stale. The listing is the
        // newer statement of what is installed.
        let inventory = NpmInventory(
            packages: [NpmGlobalPackage(name: "typescript", version: "5.7.0")],
            outdated: .fresh(
                ["typescript": NpmOutdatedRecord(current: "5.6.2", wanted: "5.7.0", latest: "5.7.0")],
                at: Self.checkedAt
            )
        )

        let typescript = try #require(inventory.installedPackages().first)

        #expect(typescript.installedVersion == "5.7.0")
        #expect(typescript.catalogVersion == "5.7.0")
        #expect(typescript.isOutdated == false)
    }

    @Test("An empty inventory projects to no rows at all, at every freshness")
    func emptyInventoryProjectsEmpty() {
        for state: NpmOutdatedState in [
            .fresh([:], at: Self.checkedAt),
            .notChecked(.notYetChecked),
            .failed(.malformedPayload),
        ] {
            #expect(NpmInventory(packages: [], outdated: state).installedPackages().isEmpty)
        }
    }
}
