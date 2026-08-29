import Foundation
import Observation

/// Observable npm detection state for the UI.
///
/// Mirrors `BrewDetectionStore` — single-flight, request-keyed, publishing only
/// genuine transitions — with one structural difference: the switch.
///
/// Homebrew is not optional in a Homebrew app, so its store evaluates
/// unconditionally. npm is optional and **off by default**, and the specification
/// is emphatic about what off means: no npm process of any kind is spawned, and
/// the published state is `disabled` rather than a hidden result. That is why
/// `isEnabled` gates the probe at its source rather than gating the *display* of
/// an answer that was computed anyway. A build with the switch off must be
/// observably identical to a build without this capability, and the only way to
/// keep that true is for the locator never to be called.
@MainActor
@Observable
public final class NpmDetectionStore {
    /// The most recent result.
    ///
    /// Starts at `.disabled` rather than `.absent`, because before the switch is
    /// on the honest answer is "not asked", not "looked and found nothing" — and
    /// the two lead to different copy: only one of them should offer help
    /// installing npm.
    public private(set) var state: NpmDetectionState = .disabled

    /// Whether the npm source is switched on.
    ///
    /// Turning it on starts detection; turning it off clears the state back to
    /// `.disabled` and makes every other trigger inert. Both without a relaunch.
    public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            guard isEnabled else {
                // Abandon anything in flight rather than letting it publish
                // after the user switched the source off.
                inFlight = nil
                nextEvaluationToken += 1
                publishedToken = nextEvaluationToken
                state = .disabled
                return
            }
            Task { await refresh() }
        }
    }

    /// The user's configured `npm` path, if any.
    public var configuredPath: URL? {
        didSet {
            guard configuredPath != oldValue else { return }
            Task { await refresh() }
        }
    }

    private let locator: any NpmLocating

    /// The one evaluation that may be joined, together with the token that owns
    /// it and the request it was started for, so a differing question can never
    /// join it.
    private struct InFlightEvaluation {
        let token: Int
        let request: URL?
        let task: Task<NpmDetectionState, Never>
    }

    @ObservationIgnored private var inFlight: InFlightEvaluation?
    @ObservationIgnored private var nextEvaluationToken = 0
    /// The token of the newest evaluation whose answer was published. Doubles as
    /// the publication ordinal: tokens are handed out in request order.
    @ObservationIgnored private var publishedToken = 0

    public init(
        locator: any NpmLocating = DefaultNpmLocator(),
        isEnabled: Bool = false,
        configuredPath: URL? = nil
    ) {
        self.locator = locator
        self.isEnabled = isEnabled
        self.configuredPath = configuredPath
    }

    /// Re-evaluates detection and publishes the result if it changed.
    ///
    /// A no-op while the source is off — not a probe whose answer is discarded.
    /// That distinction is the requirement, not an optimisation.
    public func refresh() async {
        guard isEnabled else {
            state = .disabled
            return
        }

        let path = configuredPath
        let result: NpmDetectionState
        let token: Int

        if let current = inFlight, current.request == path {
            token = current.token
            result = await current.task.value
        } else {
            nextEvaluationToken += 1
            token = nextEvaluationToken
            let evaluation = Task { [locator, weak self] in
                defer { self?.vacate(token) }
                return await locator.detect(configuredPath: path)
            }
            inFlight = InFlightEvaluation(token: token, request: path, task: evaluation)
            result = await evaluation.value
        }

        // A probe that settles after the source was switched off must not
        // resurrect a detected state.
        guard isEnabled else { return }

        // Tokens are handed out in request order, so a token that no longer
        // leads has been overtaken: its answer describes a question the user has
        // already moved on from.
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
