import Foundation
import Observation
import Synchronization
import Testing

@testable import BrewProcess

@MainActor
@Suite("Observable brew detection state", .timeLimit(.minutes(1)))
struct BrewDetectionStoreTests {
    private var detected: BrewDetectionState {
        .detected(
            BrewInstallation(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
                prefix: .appleSilicon,
                version: BrewVersion(major: 4, minor: 2, patch: 0)
            )
        )
    }

    /// Lets pending main-actor work run without depending on wall-clock time.
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    @Test("The launch evaluation publishes exactly one state")
    func launchEvaluationPublishesOnce() async {
        let locator = FakeBrewLocator(results: [detected])
        let store = BrewDetectionStore(locator: locator)
        let changes = Mutex(0)

        withObservationTracking {
            _ = store.state
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        await store.refresh()

        #expect(store.state == detected)
        #expect(changes.withLock { $0 } == 1)
        #expect(locator.callCount == 1)
    }

    @Test("A re-evaluation with an unchanged result publishes nothing new")
    func unchangedResultDoesNotRepublish() async {
        let locator = FakeBrewLocator(results: [detected])
        let store = BrewDetectionStore(locator: locator)
        await store.refresh()

        let changes = Mutex(0)
        withObservationTracking {
            _ = store.state
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        await store.refresh()

        #expect(locator.callCount == 2)
        #expect(changes.withLock { $0 } == 0)
        #expect(store.state == detected)
    }

    @Test("Brew appearing after an absent result publishes the transition")
    func focusRefreshObservesNewlyInstalledBrew() async {
        let locator = FakeBrewLocator(results: [.absent, detected])
        let store = BrewDetectionStore(locator: locator)

        await store.refresh()
        #expect(store.state == .absent)
        #expect(store.state.installGuidance != nil)

        let changes = Mutex(0)
        withObservationTracking {
            _ = store.state
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        await store.refresh()

        #expect(store.state == detected)
        #expect(changes.withLock { $0 } == 1)
    }

    @Test("A configured path that vanishes transitions off detected")
    func vanishingConfiguredPathTransitions() async {
        let configured = URL(fileURLWithPath: "/Users/tester/homebrew/bin/brew")
        let locator = FakeBrewLocator(
            results: [
                .detected(
                    BrewInstallation(
                        executableURL: configured,
                        prefix: .custom(configured),
                        version: BrewVersion(major: 4, minor: 2, patch: 0)
                    )
                ),
                .configuredPathMissing(configured),
            ]
        )
        let store = BrewDetectionStore(locator: locator, configuredPath: configured)

        await store.refresh()
        #expect(store.state.installation?.prefix == .custom(configured))

        await store.refresh()

        #expect(store.state == .configuredPathMissing(configured))
        #expect(locator.configuredPaths == [configured, configured])
    }

    @Test("Concurrent refreshes collapse into a single evaluation")
    func refreshIsSingleFlight() async {
        let locator = FakeBrewLocator(results: [detected], gated: true)
        let store = BrewDetectionStore(locator: locator)

        let first = Task { await store.refresh() }
        await locator.waitForCalls(atLeast: 1)
        let second = Task { await store.refresh() }
        await settle()

        // The second caller joined the in-flight evaluation instead of starting
        // another one.
        #expect(locator.callCount == 1)

        locator.release()
        await first.value
        await second.value

        #expect(locator.callCount == 1)
        #expect(store.state == detected)
    }

    @Test("A refresh after an in-flight one finishes evaluates again")
    func sequentialRefreshesEachEvaluate() async {
        let locator = FakeBrewLocator(results: [.absent, detected])
        let store = BrewDetectionStore(locator: locator)

        await store.refresh()
        await store.refresh()

        #expect(locator.callCount == 2)
        #expect(store.state == detected)
    }

    @Test("A settled evaluation does not answer a later re-evaluation")
    func settledEvaluationDoesNotAnswerALaterRefresh() async {
        let locator = FakeBrewLocator(results: [.absent, detected], gated: true)
        let store = BrewDetectionStore(locator: locator)

        let first = Task { await store.refresh() }
        await locator.waitForCalls(atLeast: 1)
        // The joiner asks again the instant its join resumes — the window in
        // which the settled evaluation is still parked in the slot.
        let second = Task {
            await store.refresh()
            await store.refresh()
        }
        await settle()
        #expect(locator.callCount == 1)

        locator.release()
        await first.value
        await second.value

        #expect(locator.callCount == 2)
        // The second probe resolves `detected`; inheriting the settled one would
        // leave the store on `absent`.
        #expect(store.state == detected)
    }

    @Test("An abandoned caller does not poison later re-evaluations")
    func abandonedCallerDoesNotPoisonLaterRefreshes() async {
        let locator = FakeBrewLocator(results: [.absent, detected], gated: true)
        let store = BrewDetectionStore(locator: locator)

        let abandoned = Task { await store.refresh() }
        await locator.waitForCalls(atLeast: 1)
        abandoned.cancel()

        let later = Task {
            await store.refresh()
            await store.refresh()
        }
        await settle()
        locator.release()
        await abandoned.value
        await later.value

        #expect(locator.callCount == 2)
        #expect(store.state == detected)
    }

    @Test("The state before any evaluation is the soft absent signal")
    func initialStateIsAbsent() {
        let store = BrewDetectionStore(locator: FakeBrewLocator(results: [detected]))

        #expect(store.state == .absent)
    }
}
