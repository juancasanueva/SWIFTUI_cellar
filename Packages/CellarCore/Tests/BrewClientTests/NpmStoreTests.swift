import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The npm store: two reads with two different costs, and one push into the
/// merged inventory.
@MainActor
@Suite("npm store", .timeLimit(.minutes(1)))
struct NpmStoreTests {
    private static let environment = NpmEnvironment(
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/npm"),
        version: "10.9.2",
        prefix: URL(fileURLWithPath: "/opt/homebrew"),
        origin: .homebrew
    )

    private static let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static func arrange(
        listings: [FakeNpmPayloadSource.Answer] = [.globals([("typescript", "5.6.2")])],
        reports: [FakeNpmPayloadSource.Answer] = [.payload("{}")],
        brew: [String] = ["wget"]
    ) -> (NpmStore, InstalledStore, FakeNpmPayloadSource) {
        let source = FakeNpmPayloadSource(listings: listings, reports: reports)
        let installed = InstalledStore(source: FakeInstalledPayloadSource([.formulae(brew)]))
        let store = NpmStore(
            installed: installed, source: source, clock: FixedNpmClock(checkedAt)
        )
        return (store, installed, source)
    }

    // MARK: - Listing

    @Test("A listing populates the npm inventory and the merged one together")
    func listingPublishesIntoTheMergedInventory() async {
        let (store, installed, source) = Self.arrange()
        await installed.refresh(using: TestInstallation.appleSilicon)

        await store.refreshListing(using: Self.environment)

        #expect(store.inventory.packages.map(\.name) == ["typescript"])
        #expect(installed.inventory.packages.map(\.name) == ["typescript", "wget"])
        #expect(store.isContributing)
        #expect(source.listingCount == 1)
        // The cheap local read must not have dragged the expensive remote one
        // along with it.
        #expect(source.reportCount == 0)
    }

    @Test("A listing failure keeps the last good rows and records the reason")
    func listingFailureIsNotAnEviction() async {
        let (store, installed, _) = Self.arrange(
            listings: [.globals([("typescript", "5.6.2")]), .failure(.networkUnavailable)]
        )
        await installed.refresh(using: TestInstallation.appleSilicon)
        await store.refreshListing(using: Self.environment)

        await store.refreshListing(using: Self.environment)

        #expect(store.listingFailure == .networkUnavailable)
        #expect(store.inventory.packages.map(\.name) == ["typescript"])
        #expect(installed.inventory.packages.map(\.name) == ["typescript", "wget"])
    }

    @Test("A malformed listing is a failure rather than an empty inventory")
    func malformedListingDoesNotEmptyTheList() async {
        let (store, installed, _) = Self.arrange(
            listings: [.globals([("typescript", "5.6.2")]), .payload("not json")]
        )
        await installed.refresh(using: TestInstallation.appleSilicon)
        await store.refreshListing(using: Self.environment)

        await store.refreshListing(using: Self.environment)

        #expect(store.listingFailure == .malformedPayload)
        #expect(store.inventory.packages.map(\.name) == ["typescript"])
    }

    @Test("A recovered listing clears the recorded failure")
    func recoveryClearsTheFailure() async {
        let (store, _, _) = Self.arrange(
            listings: [.failure(.networkUnavailable), .globals([("corepack", "0.29.4")])]
        )

        await store.refreshListing(using: Self.environment)
        #expect(store.listingFailure == .networkUnavailable)

        await store.refreshListing(using: Self.environment)

        #expect(store.listingFailure == nil)
        #expect(store.inventory.packages.map(\.name) == ["corepack"])
    }

    // MARK: - Outdated

    @Test("A completed check is fresh, stamped with the clock, and marks the rows")
    func outdatedCheckMarksTheRows() async {
        let (store, installed, source) = Self.arrange(
            reports: [.report([("typescript", current: "5.6.2", latest: "5.7.0")])]
        )
        await installed.refresh(using: TestInstallation.appleSilicon)
        await store.refreshListing(using: Self.environment)

        await store.refreshOutdated(using: Self.environment)

        #expect(store.inventory.outdated.checkedAt == Self.checkedAt)
        #expect(store.inventory.outdated.isUpToDate == false)
        #expect(installed.inventory.outdatedIDs == [PackageID(kind: .npm, name: "typescript")])
        #expect(source.reportCount == 1)
    }

    @Test("A network failure is failed, and never reads as up to date")
    func offlineCheckIsFailed() async {
        let (store, installed, _) = Self.arrange(reports: [.failure(.networkUnavailable)])
        await installed.refresh(using: TestInstallation.appleSilicon)
        await store.refreshListing(using: Self.environment)

        await store.refreshOutdated(using: Self.environment)

        #expect(store.inventory.outdated.failure == .networkUnavailable)
        #expect(store.inventory.outdated.isUpToDate == false)
        // Present and unmarked: the packages are installed either way.
        #expect(installed.inventory.packages.map(\.name) == ["typescript", "wget"])
        #expect(installed.inventory.outdatedIDs.isEmpty)
    }

    @Test("A cancelled check is not checked rather than failed")
    func cancelledCheckIsNotAFailure() async {
        let (store, _, _) = Self.arrange(reports: [.failure(.cancelled)])
        await store.refreshListing(using: Self.environment)

        await store.refreshOutdated(using: Self.environment)

        #expect(store.inventory.outdated == .notChecked(.cancelled))
        #expect(store.inventory.outdated.failure == nil)
    }

    @Test("A clean check is fresh and up to date")
    func cleanCheckIsUpToDate() async {
        let (store, installed, _) = Self.arrange()
        await installed.refresh(using: TestInstallation.appleSilicon)
        await store.refreshListing(using: Self.environment)

        await store.refreshOutdated(using: Self.environment)

        #expect(store.inventory.outdated.isUpToDate)
        #expect(installed.inventory.outdatedIDs.isEmpty)
    }

    @Test("A later listing keeps the freshness the check established")
    func listingDoesNotResetFreshness() async {
        let (store, _, _) = Self.arrange(
            listings: [.globals([("typescript", "5.6.2")]), .globals([("typescript", "5.6.2")])],
            reports: [.report([("typescript", current: "5.6.2", latest: "5.7.0")])]
        )
        await store.refreshListing(using: Self.environment)
        await store.refreshOutdated(using: Self.environment)

        await store.refreshListing(using: Self.environment)

        // Resetting to `notChecked` here would make the machine flicker between
        // "an update is available" and "not checked" on every local re-read.
        #expect(store.inventory.outdated.checkedAt == Self.checkedAt)
        #expect(store.inventory.outdated.latest(for: "typescript") == "5.7.0")
    }

    // MARK: - Detection

    @Test("A detected npm contributes; every other detection state withdraws")
    func detectionDrivesContribution() async {
        for state: NpmDetectionState in [
            .disabled,
            .absent,
            .invalid(URL(fileURLWithPath: "/x/npm"), .notExecutable),
            .configuredPathMissing(URL(fileURLWithPath: "/x/npm")),
        ] {
            let (store, installed, source) = Self.arrange()
            await installed.refresh(using: TestInstallation.appleSilicon)
            await store.apply(.detected(Self.environment))
            #expect(installed.inventory.packages.count == 2)

            await store.apply(state)

            #expect(installed.inventory.packages.map(\.name) == ["wget"])
            #expect(store.isContributing == false)
            #expect(store.inventory.packages.isEmpty)
            // Withdrawing spawns nothing.
            #expect(source.listingCount == 1)
        }
    }

    @Test("Withdrawing before ever contributing touches the merged inventory not at all")
    func withdrawingWithoutContributingIsInert() async {
        let (store, installed, _) = Self.arrange()
        await installed.refresh(using: TestInstallation.appleSilicon)
        let before = installed.inventory

        store.withdraw()

        #expect(installed.inventory == before)
        #expect(store.isContributing == false)
    }
}
