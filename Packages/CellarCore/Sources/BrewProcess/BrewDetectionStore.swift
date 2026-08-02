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
    /// it, so a settling probe can only ever vacate its own entry (design D3),
    /// and the *request* it was started for, so a differing question can never
    /// join it (design D6).
    private struct InFlightEvaluation {
        let token: Int
        let request: URL?
        let task: Task<BrewDetectionState, Never>
    }

    @ObservationIgnored private var inFlight: InFlightEvaluation?
    @ObservationIgnored private var nextEvaluationToken = 0
    /// The token of the newest evaluation whose answer was published. Doubles as
    /// the publication ordinal: tokens are handed out in request order.
    @ObservationIgnored private var publishedToken = 0

    public init(
        locator: any BrewLocating = DefaultBrewLocator(),
        configuredPath: URL? = nil
    ) {
        self.locator = locator
        self.configuredPath = configuredPath
    }

    /// Re-evaluates detection and publishes the result if it changed.
    ///
    /// Only an evaluation *genuinely in flight* may be joined, and only by a
    /// caller asking the same question. The probe vacates its own slot from
    /// inside its body, so the slot is empty before any joiner resumes and a
    /// settled or abandoned evaluation can never be handed back as a fresh
    /// answer (design D3). No drain is needed here: detection has no `cancel()`
    /// and stages nothing.
    ///
    /// The slot is keyed by the **request** — the configured path the evaluation
    /// was started for. Repointing `brew` mid-evaluation asks a different
    /// question, so it starts its own probe rather than adopting an answer
    /// computed for the previous path (design D6).
    public func refresh() async {
        let path = configuredPath
        let result: BrewDetectionState
        let token: Int

        if let current = inFlight, current.request == path {
            token = current.token
            result = await current.task.value
        } else {
            nextEvaluationToken += 1
            token = nextEvaluationToken
            // `weak self` keeps the probe from retaining the store, as before.
            let evaluation = Task { [locator, weak self] in
                defer { self?.vacate(token) }
                return await locator.detect(configuredPath: path)
            }
            inFlight = InFlightEvaluation(token: token, request: path, task: evaluation)
            result = await evaluation.value
        }

        // Tokens are handed out in request order, so a token that no longer
        // leads has been overtaken: its answer describes a question the user has
        // already moved on from. The resident state must correspond to the
        // request most recently *asked for*, not to whichever probe happened to
        // settle last.
        guard token > publishedToken else { return }
        publishedToken = token

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
