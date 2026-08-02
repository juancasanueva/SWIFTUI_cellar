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

    /// The one evaluation that may be joined, together with the token that owns
    /// it, so a settling probe can only ever vacate its own entry (design D3).
    private struct InFlightEvaluation {
        let token: Int
        let task: Task<BrewDetectionState, Never>
    }

    @ObservationIgnored private var inFlight: InFlightEvaluation?
    @ObservationIgnored private var nextEvaluationToken = 0

    public init(
        locator: any BrewLocating = DefaultBrewLocator(),
        configuredPath: URL? = nil
    ) {
        self.locator = locator
        self.configuredPath = configuredPath
    }

    /// Re-evaluates detection and publishes the result if it changed.
    ///
    /// Only an evaluation *genuinely in flight* may be joined. The probe vacates
    /// its own slot from inside its body, so the slot is empty before any joiner
    /// resumes and a settled or abandoned evaluation can never be handed back as
    /// a fresh answer (design D3). No drain is needed here: detection has no
    /// `cancel()` and stages nothing.
    public func refresh() async {
        let result: BrewDetectionState
        if let current = inFlight {
            result = await current.task.value
        } else {
            let path = configuredPath
            nextEvaluationToken += 1
            let token = nextEvaluationToken
            // `weak self` keeps the probe from retaining the store, as before.
            let evaluation = Task { [locator, weak self] in
                defer { self?.vacate(token) }
                return await locator.detect(configuredPath: path)
            }
            inFlight = InFlightEvaluation(token: token, task: evaluation)
            result = await evaluation.value
        }

        // Assigning an identical value would notify observers of a transition
        // that did not happen.
        guard state != result else { return }
        state = result
    }

    private func vacate(_ token: Int) {
        guard inFlight?.token == token else { return }
        inFlight = nil
    }
}
