import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// The services list as the UI sees it.
///
/// Deliberately `InstalledStoreTests`' shape: the store is the same store over
/// a different projection, and the three properties M2-0 paid for — a
/// request-keyed single flight, an ordinal-guarded adoption, and a last-good
/// list that survives a failure — have to hold here too or a transient brew
/// lock empties the user's services list every five seconds.
@MainActor
@Suite("Services store", .timeLimit(.minutes(1)))
struct ServicesStoreTests {
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    // MARK: - Request-keyed single flight

    @Test("Two overlapping refreshes perform one acquisition and see the same list")
    func overlappingRefreshesCoalesce() async {
        let source = FakeServicesPayloadSource([.services(["atuin"])], gated: true)
        let store = ServicesStore(source: source)

        let first = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)
        let second = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await settle()

        #expect(source.callCount == 1, "a poll tick started a second acquisition of the same thing")

        source.release()
        await first.value
        await second.value

        #expect(source.callCount == 1)
        #expect(store.services.map(\.name) == ["atuin"])
    }

    /// The mark, not just the request key. A refresh asked for *after* a
    /// mutation invalidated the list observed the world before that change, so
    /// it must not be handed back as the answer.
    @Test("A refresh requested after an invalidation does not join the acquisition before it")
    func anInvalidationStopsAJoin() async {
        let source = FakeServicesPayloadSource(
            [.services(["atuin"], status: "none"), .services(["atuin"], status: "started")],
            gated: true
        )
        let store = ServicesStore(source: source)

        let stale = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)

        store.invalidate()
        let fresh = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 2)

        #expect(source.callCount == 2, "the post-invalidation refresh joined a pre-change probe")

        source.release()
        await stale.value
        await fresh.value
    }

    @Test("A refresh under a different installation does not join the one in flight")
    func differentInstallationDoesNotJoin() async {
        let source = FakeServicesPayloadSource(
            [.services(["from-apple-silicon"]), .services(["from-intel"])],
            gated: true
        )
        let store = ServicesStore(source: source)

        let first = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)
        let second = Task { await store.refresh(using: TestInstallation.intel) }
        await source.waitForCalls(atLeast: 2)

        #expect(source.callCount == 2)
        #expect(source.installations.map(\.executableURL) == [
            TestInstallation.appleSilicon.executableURL,
            TestInstallation.intel.executableURL
        ])

        source.release()
        await first.value
        await second.value
    }

    // MARK: - Ordinal-guarded adoption

    @Test("An older answer arriving after a newer one is discarded, not installed")
    func lateOlderAdoptionIsDiscarded() async {
        let source = FakeServicesPayloadSource(
            [.services(["older-answer"]), .services(["newer-answer"])],
            gated: true
        )
        let store = ServicesStore(source: source)

        let older = Task { await store.refresh(using: TestInstallation.appleSilicon) }
        await source.waitForCalls(atLeast: 1)
        let newer = Task { await store.refresh(using: TestInstallation.intel) }
        await source.waitForCalls(atLeast: 2)

        source.release(call: 1)
        await newer.value
        #expect(store.services.map(\.name) == ["newer-answer"])

        source.release(call: 0)
        await older.value
        await settle()

        #expect(store.services.map(\.name) == ["newer-answer"], "a slow answer landed on a fresh one")
    }

    // MARK: - Failure keeps the last good list

    @Test("A failed refresh keeps the last good list and reports the failure")
    func failureKeepsTheLastGoodList() async {
        let source = FakeServicesPayloadSource([
            .services(["atuin"]),
            .failure(.commandFailed(status: 1, message: "Error: locked"))
        ])
        let store = ServicesStore(source: source)

        await store.refresh(using: TestInstallation.appleSilicon)
        #expect(store.state == .loaded)

        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(store.state == .failed(.commandFailed(status: 1, message: "Error: locked")))
        #expect(store.services.map(\.name) == ["atuin"], "a brew lock emptied the services list")
    }

    @Test("A malformed payload is a failure, not an empty list")
    func malformedPayloadKeepsTheLastGoodList() async {
        let source = FakeServicesPayloadSource([
            .services(["atuin"]),
            .payload("not the documented payload")
        ])
        let store = ServicesStore(source: source)

        await store.refresh(using: TestInstallation.appleSilicon)
        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(store.state == .failed(.malformedPayload))
        #expect(store.services.map(\.name) == ["atuin"])
    }

    // MARK: - SM11 — brew absent

    @Test("Absent brew gives an empty list with guidance and no spawn")
    func absentBrewGivesAnEmptyListWithGuidanceAndNoSpawn() async {
        let launcher = RecordingProcessLauncher()
        let source = FakeServicesPayloadSource([.services(["atuin"])])
        let store = ServicesStore(source: source)

        await store.refresh(for: .absent)

        #expect(store.services.isEmpty)
        #expect(source.callCount == 0, "a probe ran with no brew to probe")
        #expect(launcher.launchCount == 0, "a process was spawned with no brew")
        #expect(store.state == .brewAbsent(.notInstalled(.standard)))
        // Guidance, not an error state — and it is the same guidance the rest
        // of the app shows.
        #expect(store.absence?.installGuidance == BrewInstallGuidance.standard)
        #expect(store.absence?.title == "Homebrew is not installed")
    }

    @Test("An invalid configured path is guidance carrying the rejection reason")
    func invalidConfiguredPathIsGuidance() async {
        let configured = URL(fileURLWithPath: "/Users/tester/brew")
        let source = FakeServicesPayloadSource([.services(["atuin"])])
        let store = ServicesStore(source: source)

        await store.refresh(for: .invalid(configured, .notExecutable(configured)))

        #expect(store.services.isEmpty)
        #expect(source.callCount == 0)
        #expect(store.absence?.rejectionReason == .notExecutable(configured))
        #expect(store.absence?.installGuidance == nil)
    }

    @Test("The list populates when brew appears, with no restart")
    func listPopulatesWhenBrewAppears() async {
        let source = FakeServicesPayloadSource([.services(["atuin", "postgresql"])])
        let store = ServicesStore(source: source)

        await store.refresh(for: .absent)
        #expect(store.services.isEmpty)

        await store.refresh(for: .detected(TestInstallation.appleSilicon))

        #expect(store.state == .loaded)
        #expect(store.services.map(\.name) == ["atuin", "postgresql"])
        #expect(source.callCount == 1)
    }

    // MARK: - SM9 — no stale status is retained

    @Test("A changed status replaces the previous one rather than being retained")
    func aChangedStatusReplacesThePreviousOne() async {
        let source = FakeServicesPayloadSource([
            .services(["atuin"], status: "started"),
            .services(["atuin"], status: "error")
        ])
        let store = ServicesStore(source: source)

        await store.refresh(using: TestInstallation.appleSilicon)
        #expect(store.services.map(\.status) == [.started])

        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(store.services.map(\.status) == [.error])
        #expect(
            store.services.contains { $0.status == .started } == false,
            "the previously displayed status was still being shown"
        )
    }

    // MARK: - SM2 — detail is selection-keyed

    @Test("Detail is fetched only for the selected service, once, and never with --all")
    func detailIsFetchedOnlyForTheSelectedService() async {
        let source = FakeServicesPayloadSource([.services(["atuin", "postgresql", "redis"])])
        let details = FakeServiceDetailSource()
        let store = ServicesStore(source: source, detailSource: details)

        await store.refresh(using: TestInstallation.appleSilicon)
        #expect(details.callCount == 0, "a list refresh fetched detail")

        await store.select("atuin")

        #expect(details.requested == ["atuin"])
        #expect(store.detail?.name == "atuin")
        #expect(store.detail?.logPaths.count == 1)
    }

    @Test("Deselecting drops the detail and fetches nothing")
    func deselectingDropsTheDetail() async {
        let source = FakeServicesPayloadSource([.services(["atuin"])])
        let details = FakeServiceDetailSource()
        let store = ServicesStore(source: source, detailSource: details)

        await store.refresh(using: TestInstallation.appleSilicon)
        await store.select("atuin")
        #expect(store.detail != nil)

        await store.select(nil)

        #expect(store.detail == nil)
        #expect(details.callCount == 1, "deselecting probed brew")
    }

    /// A name the argv gate refuses never becomes a probe. There is no second,
    /// weaker door into the detail read.
    @Test("A service whose name could not survive argv is never probed for detail")
    func anUnsafeNameIsNeverProbed() async {
        let source = FakeServicesPayloadSource([.services(["atuin"])])
        let details = FakeServiceDetailSource()
        let store = ServicesStore(source: source, detailSource: details)

        await store.refresh(using: TestInstallation.appleSilicon)
        await store.select("--all")

        #expect(details.callCount == 0, "an unvalidated name reached the detail probe")
        #expect(store.detail == nil)
    }
}
