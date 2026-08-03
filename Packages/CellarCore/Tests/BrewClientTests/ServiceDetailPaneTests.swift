import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// What the detail pane says, and whether it is true.
///
/// The same defect `ServicesEmptyStateTests` closed for the list, one pane over:
/// `ServiceDetailView` branched on `detail != nil` alone, so a probe that
/// **failed** rendered as "No service selected" — a reassuring absence in place
/// of a failure, with brew's reason discarded inside `select`'s `catch`. Nothing
/// selected, reading, loaded and failed are four different facts; a surface that
/// can express two of them is lying about the other two.
///
/// So the decision is a value, projected in `ServicesPresentation` where
/// `swift test` reaches it, exactly as `emptyState` already is.
@Suite("Service detail pane")
struct ServiceDetailPaneTests {
    private static let detail = ServiceDetail(
        name: "atuin",
        status: .started,
        user: "tester",
        pid: 4242,
        plistPath: nil,
        logPaths: []
    )

    private static let everyState: [ServiceDetailLoadState] = [
        .idle,
        .loading("atuin"),
        .loaded(detail),
        .failed(name: "atuin", reason: .probe(.brewUnavailable)),
        .failed(name: "atuin", reason: .probe(.commandFailed(status: 1, message: "Error: locked"))),
        .failed(name: "atuin", reason: .probe(.malformedPayload)),
        .failed(name: "atuin", reason: .probe(.cancelled)),
        .failed(name: "--all", reason: .unusableName),
        .failed(name: "atuin", reason: .noInstallation)
    ]

    // MARK: - The state that is genuinely an absence

    @Test("Only an empty selection says no service is selected")
    func onlyAnEmptySelectionSaysNoServiceIsSelected() {
        #expect(ServiceDetailLoadState.idle.pane == .notice(.nothingSelected))
        #expect(ServiceDetailNotice.nothingSelected.title == "No service selected")

        let claiming = Self.everyState.filter { $0.pane == .notice(.nothingSelected) }
        #expect(claiming.count == 1, "\(claiming.count) states claim nothing is selected")
    }

    // MARK: - The states that are not

    @Test("A probe still in flight says it is reading, naming the service")
    func aProbeInFlightSaysItIsReading() {
        let pane = ServiceDetailLoadState.loading("atuin").pane

        #expect(pane == .notice(.reading("atuin")))
        guard case .notice(let notice) = pane else { return }
        #expect(notice.title.contains("atuin"))
        #expect(notice.title != "No service selected", "an unanswered probe reads as an empty selection")
        #expect(notice.message.isEmpty == false)
    }

    @Test("A failed probe reports the failure, names the service, and carries brew's reason")
    func aFailedProbeReportsTheFailure() {
        let failures: [ServiceDetailFailure] = [
            .probe(.brewUnavailable),
            .probe(.commandFailed(status: 1, message: "Error: brew is locked")),
            .probe(.malformedPayload),
            .probe(.cancelled),
            .unusableName,
            .noInstallation
        ]

        for failure in failures {
            let pane = ServiceDetailLoadState.failed(name: "atuin", reason: failure).pane

            #expect(
                pane == .notice(.failed(service: "atuin", reason: failure.shortDescription)),
                "\(failure)"
            )
            guard case .notice(let notice) = pane else {
                Issue.record("\(failure) rendered as loaded detail")
                continue
            }
            #expect(notice.title == "Could not read atuin", "\(failure)")
            #expect(notice.title != "No service selected", "\(failure) is presented as an absence")
            #expect(notice.message == failure.shortDescription, "the reason is discarded instead of shown")
            #expect(notice.message.isEmpty == false, "\(failure)")
        }
    }

    /// brew's own words whenever it produced any, exactly as
    /// `ServicesError.shortDescription` already promises for the list.
    @Test("Each way a detail probe can fail explains itself differently")
    func eachFailureExplainsItselfDifferently() {
        #expect(
            ServiceDetailFailure.probe(.commandFailed(status: 1, message: "Error: brew is locked"))
                .shortDescription == "Error: brew is locked"
        )

        let reasons = [
            ServiceDetailFailure.probe(.brewUnavailable),
            .unusableName,
            .noInstallation
        ].map(\.shortDescription)

        #expect(Set(reasons).count == 3, "two unrelated failures give the user the same sentence")
        for reason in reasons {
            #expect(reason.isEmpty == false)
        }
    }

    // MARK: - The state that has content

    @Test("An answered probe is the only state that renders detail")
    func onlyAnAnsweredProbeRendersDetail() {
        #expect(ServiceDetailLoadState.loaded(Self.detail).pane == .detail(Self.detail))

        let rendering = Self.everyState.filter {
            if case .detail = $0.pane { return true }
            return false
        }
        #expect(rendering.count == 1, "\(rendering.count) states render detail")
    }

    // MARK: - The mapping is total and loses nothing

    @Test("The four outcomes stay four, and every notice explains itself")
    func theFourOutcomesStayFour() {
        var headlines: Set<String> = []

        for state in Self.everyState {
            switch state.pane {
            case .detail:
                headlines.insert("<detail>")
            case .notice(let notice):
                #expect(notice.title.isEmpty == false, "\(state) has no headline")
                #expect(notice.message.isEmpty == false, "\(state) has no explanation")
                headlines.insert(notice.title)
            }
        }

        // nothing selected / reading atuin / could not read atuin /
        // could not read --all / detail. Four states, five headlines, because
        // the two that name a service name a different one.
        #expect(headlines.count == 5, "\(headlines.sorted())")
    }
}

/// What the store keeps when a detail probe does not answer.
///
/// The projection above can only be as honest as its input, and the input was
/// being thrown away: `select`'s `catch` bound `error` and discarded it, leaving
/// `detail == nil` with `selected` still set — indistinguishable from nothing
/// having been selected at all.
@MainActor
@Suite("Service detail probe outcome", .timeLimit(.minutes(1)))
struct ServiceDetailProbeTests {
    private static func store(
        details: FakeServiceDetailSource
    ) -> (ServicesStore, FakeServicesPayloadSource) {
        let source = FakeServicesPayloadSource([.services(["atuin", "postgresql"])])
        return (ServicesStore(source: source, detailSource: details), source)
    }

    @Test("A failed probe keeps the reason it failed rather than reading as no selection")
    func aFailedProbeKeepsItsReason() async {
        // No payload for "postgresql", so the source refuses it.
        let details = FakeServiceDetailSource()
        let (store, _) = Self.store(details: details)
        await store.refresh(using: TestInstallation.appleSilicon)

        await store.select("postgresql")

        #expect(store.detailState == .failed(name: "postgresql", reason: .probe(.malformedPayload)))
        #expect(store.detail == nil)
        #expect(
            store.detailState.pane != .notice(.nothingSelected),
            "a failed probe is reported to the user as nothing having been selected"
        )
        guard case .notice(let notice) = store.detailState.pane else {
            Issue.record("a failed probe rendered as detail")
            return
        }
        #expect(notice.title == "Could not read postgresql")
        #expect(notice.message == ServicesError.malformedPayload.shortDescription)
    }

    @Test("A name the argv gate refuses reports that, and is still never probed")
    func anUnsafeNameReportsItselfAndIsNeverProbed() async {
        let details = FakeServiceDetailSource()
        let (store, _) = Self.store(details: details)
        await store.refresh(using: TestInstallation.appleSilicon)

        await store.select("--all")

        #expect(details.callCount == 0, "an unvalidated name reached the detail probe")
        #expect(store.detailState == .failed(name: "--all", reason: .unusableName))
        #expect(store.detailState.pane != .notice(.nothingSelected))
    }

    @Test("A selection made before brew was located says so instead of reading forever")
    func aSelectionWithoutAnInstallationSaysSo() async {
        let details = FakeServiceDetailSource()
        let (store, _) = Self.store(details: details)

        await store.select("atuin")

        #expect(details.callCount == 0)
        #expect(store.detailState == .failed(name: "atuin", reason: .noInstallation))
        #expect(store.detailState.pane != .notice(.reading("atuin")), "nothing is in flight")
    }

    @Test("A probe still in flight reads as reading, not as an empty selection")
    func anInFlightProbeReadsAsReading() async throws {
        let details = FakeServiceDetailSource(gated: true)
        let (store, _) = Self.store(details: details)
        await store.refresh(using: TestInstallation.appleSilicon)

        let probe = Task { await store.select("atuin") }
        await details.waitForCalls(atLeast: 1)

        #expect(store.detailState == .loading("atuin"))
        #expect(store.detailState.pane == .notice(.reading("atuin")))

        details.release()
        await probe.value
        #expect(store.detail?.name == "atuin")
        #expect(store.detailState.pane == .detail(try #require(store.detail)))
    }

    /// The stale-selection guard covers failures too. A user clicking faster
    /// than brew answers must not be shown the previous service's failure any
    /// more than the previous service's log paths.
    @Test("A failure belonging to a superseded selection is discarded, not shown")
    func aSupersededFailureIsDiscarded() async {
        let details = FakeServiceDetailSource([:], gated: true)
        let (store, _) = Self.store(details: details)
        await store.refresh(using: TestInstallation.appleSilicon)

        let probe = Task { await store.select("atuin") }
        await details.waitForCalls(atLeast: 1)
        // Deselected before brew answered.
        await store.select(nil)
        details.release()
        await probe.value

        #expect(store.selected == nil)
        #expect(
            store.detailState == .idle,
            "a superseded service's failure was installed over the live selection"
        )
        #expect(store.detailState.pane == .notice(.nothingSelected))
    }

    @Test("Deselecting is the only thing that reads as no selection")
    func deselectingIsTheOnlyEmptySelection() async throws {
        let details = FakeServiceDetailSource()
        let (store, _) = Self.store(details: details)
        await store.refresh(using: TestInstallation.appleSilicon)
        await store.select("atuin")
        #expect(store.detailState.pane == .detail(try #require(store.detail)))

        await store.select(nil)

        #expect(store.detailState == .idle)
        #expect(store.detailState.pane == .notice(.nothingSelected))
        #expect(details.callCount == 1, "deselecting probed brew")
    }
}
