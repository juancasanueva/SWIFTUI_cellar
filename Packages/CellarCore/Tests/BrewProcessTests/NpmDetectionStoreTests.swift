import Foundation
import Observation
import Synchronization
import Testing

@testable import BrewProcess

/// The store's whole reason to differ from `BrewDetectionStore` is the switch.
/// Homebrew is not optional in a Homebrew app; npm is, it is off by default, and
/// "off" has to mean *nothing happens* rather than "we looked and hid the
/// result".
@MainActor
@Suite("Observable npm detection state", .timeLimit(.minutes(1)))
struct NpmDetectionStoreTests {
    private var detected: NpmDetectionState {
        .detected(
            NpmEnvironment(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/npm"),
                version: "10.9.2",
                prefix: URL(fileURLWithPath: "/opt/homebrew"),
                origin: .homebrew
            )
        )
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    // MARK: - Off means nothing happens

    @Test("A store that was never enabled publishes disabled and probes nothing")
    func disabledByDefaultProbesNothing() async {
        let locator = FakeNpmLocator(results: [detected])
        let store = NpmDetectionStore(locator: locator)

        #expect(store.state == .disabled)

        await store.refresh()
        await settle()

        #expect(store.state == .disabled)
        #expect(locator.callCount == 0)
        #expect(store.state.environment == nil)
    }

    @Test("Disabled is published rather than absent, so nothing offers to install npm")
    func disabledIsNotAbsent() async {
        let store = NpmDetectionStore(locator: FakeNpmLocator(results: [.absent]))

        #expect(store.state == .disabled)
        #expect(store.state != .absent)
    }

    // MARK: - The switch

    @Test("Enabling starts detection without a relaunch")
    func enablingStartsDetection() async {
        let locator = FakeNpmLocator(results: [detected])
        let store = NpmDetectionStore(locator: locator)

        store.isEnabled = true
        await settle()

        #expect(store.state == detected)
        #expect(locator.callCount == 1)
    }

    @Test("Disabling clears the detected state and stops probing")
    func disablingClearsState() async {
        let locator = FakeNpmLocator(results: [detected])
        let store = NpmDetectionStore(locator: locator)
        store.isEnabled = true
        await settle()
        #expect(store.state == detected)

        store.isEnabled = false
        await settle()
        let callsAtDisable = locator.callCount

        // Every trigger that would normally re-evaluate is now inert.
        await store.refresh()
        store.configuredPath = URL(fileURLWithPath: "/opt/tools/npm")
        await settle()

        #expect(store.state == .disabled)
        #expect(locator.callCount == callsAtDisable)
    }

    @Test("Setting the switch to the value it already holds re-evaluates nothing")
    func idempotentToggleDoesNotReprobe() async {
        let locator = FakeNpmLocator(results: [detected])
        let store = NpmDetectionStore(locator: locator)
        store.isEnabled = true
        await settle()

        store.isEnabled = true
        await settle()

        #expect(locator.callCount == 1)
    }

    // MARK: - Single flight and request keying

    @Test("Overlapping refreshes join one evaluation instead of spawning two")
    func refreshIsSingleFlight() async {
        let locator = FakeNpmLocator(results: [detected], gated: true)
        let store = NpmDetectionStore(locator: locator, isEnabled: true)

        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        await locator.waitForCalls(atLeast: 1)
        await settle()
        locator.release()
        _ = await (first, second)

        #expect(locator.callCount == 1)
        #expect(store.state == detected)
    }

    @Test("A refresh after settlement runs fresh rather than reusing the last answer")
    func settledEvaluationIsNotReused() async {
        let locator = FakeNpmLocator(results: [detected])
        let store = NpmDetectionStore(locator: locator, isEnabled: true)

        await store.refresh()
        await store.refresh()

        #expect(locator.callCount == 2)
    }

    @Test("A refresh asking about a different path does not join the one in flight")
    func requestKeyingKeepsDifferentPathsApart() async {
        let configured = URL(fileURLWithPath: "/opt/tools/npm")
        let locator = FakeNpmLocator(
            resultsByPath: [nil: .absent, configured: detected],
            gated: true
        )
        let store = NpmDetectionStore(locator: locator, isEnabled: true)

        async let discovered: Void = store.refresh()
        await locator.waitForCalls(atLeast: 1)
        store.configuredPath = configured
        await settle()
        locator.release()
        await discovered
        await settle()

        #expect(locator.callCount == 2)
        #expect(locator.configuredPaths.contains(configured))
        #expect(store.state == detected)
    }

    @Test("Changing the configured path re-evaluates; setting it to the same value does not")
    func configuredPathChangeTriggersOneEvaluation() async {
        let configured = URL(fileURLWithPath: "/opt/tools/npm")
        let locator = FakeNpmLocator(resultsByPath: [configured: detected])
        let store = NpmDetectionStore(locator: locator, isEnabled: true)

        store.configuredPath = configured
        await settle()
        store.configuredPath = configured
        await settle()

        #expect(locator.callCount == 1)
        #expect(store.state == detected)
    }

    // MARK: - Observation

    @Test("An unchanged result publishes no observation change")
    func unchangedResultDoesNotRepublish() async {
        let locator = FakeNpmLocator(results: [detected])
        let store = NpmDetectionStore(locator: locator, isEnabled: true)
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
    }

    // MARK: - Brew is untouched

    /// A brew installation to detect. Deliberately built here rather than shared
    /// with `BrewDetectionStoreTests`: the claim under test is that the two
    /// detections stay strangers, and a shared fixture is the first thing that
    /// would quietly tie them together.
    private var brewDetected: BrewDetectionState {
        .detected(
            BrewInstallation(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
                prefix: .appleSilicon,
                version: BrewVersion(major: 4, minor: 2, patch: 0)
            )
        )
    }

    @Test("A held npm evaluation neither delays a brew transition nor republishes brew when released")
    func heldNpmEvaluationDoesNotCoupleToBrewDetection() async {
        let npmLocator = FakeNpmLocator(results: [detected], gated: true)
        let npm = NpmDetectionStore(locator: npmLocator, isEnabled: true)
        let brewLocator = FakeBrewLocator(results: [brewDetected])
        let brew = BrewDetectionStore(locator: brewLocator)

        // An npm evaluation that will not answer until it is released.
        async let npmEvaluation: Void = npm.refresh()
        await npmLocator.waitForCalls(atLeast: 1)

        // Brew is asked meanwhile and must reach its own answer unaided.
        let brewTransitionsWhileNpmIsHeld = Mutex(0)
        withObservationTracking {
            _ = brew.state
        } onChange: {
            brewTransitionsWhileNpmIsHeld.withLock { $0 += 1 }
        }

        await brew.refresh()
        await settle()

        #expect(brew.state == brewDetected)
        #expect(brewTransitionsWhileNpmIsHeld.withLock { $0 } == 1)
        #expect(brewLocator.callCount == 1)
        // The gate is still shut, so npm has genuinely not answered yet: brew's
        // observers were notified first.
        #expect(npmLocator.callCount == 1)
        #expect(npm.state == .disabled)

        // Releasing npm publishes npm's own transition and nothing of brew's.
        let brewRepublicationsAfterRelease = Mutex(0)
        withObservationTracking {
            _ = brew.state
        } onChange: {
            brewRepublicationsAfterRelease.withLock { $0 += 1 }
        }

        npmLocator.release()
        await npmEvaluation
        await settle()

        #expect(npm.state == detected)
        #expect(brew.state == brewDetected)
        #expect(brewRepublicationsAfterRelease.withLock { $0 } == 0)
        #expect(brewLocator.callCount == 1)
    }


    @Test("The brew detection store still starts absent and knows nothing of npm")
    func brewVocabularyIsUnchanged() async {
        let brew = BrewDetectionStore(locator: FakeBrewLocator(results: [.absent]))

        #expect(brew.state == .absent)
        // There is no `isEnabled` on the brew store to reach for, and no npm
        // case in its state: this suite would not compile if either arrived.
        await brew.refresh()
        #expect(brew.state == .absent)
    }
}
