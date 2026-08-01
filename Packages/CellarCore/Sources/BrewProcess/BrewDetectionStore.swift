import Foundation
import Observation

/// Observable detection state for the UI.
///
/// Re-evaluated at launch, when the app becomes active, and whenever the
/// configured path may have changed. `refresh()` is single-flight: overlapping
/// callers join the evaluation already running instead of spawning another
/// `brew --version` probe, which matters because window focus can fire in
/// bursts.
@MainActor
@Observable
public final class BrewDetectionStore {
    /// The most recent result.
    ///
    /// Starts at `.absent` because absence is a soft signal that gates nothing:
    /// before the first evaluation the honest answer is "no brew known yet",
    /// and the UI renders exactly the same guidance either way.
    public private(set) var state: BrewDetectionState = .absent

    /// The user's configured `brew` path, if any.
    public var configuredPath: URL? {
        didSet {
            guard configuredPath != oldValue else { return }
            Task { await refresh() }
        }
    }

    private let locator: any BrewLocating
    @ObservationIgnored private var inFlight: Task<BrewDetectionState, Never>?

    public init(
        locator: any BrewLocating = DefaultBrewLocator(),
        configuredPath: URL? = nil
    ) {
        self.locator = locator
        self.configuredPath = configuredPath
    }

    /// Re-evaluates detection and publishes the result if it changed.
    public func refresh() async {
        let result: BrewDetectionState
        if let inFlight {
            result = await inFlight.value
        } else {
            let path = configuredPath
            let evaluation = Task { [locator] in await locator.detect(configuredPath: path) }
            inFlight = evaluation
            result = await evaluation.value
            inFlight = nil
        }

        // Assigning an identical value would notify observers of a transition
        // that did not happen.
        guard state != result else { return }
        state = result
    }
}
