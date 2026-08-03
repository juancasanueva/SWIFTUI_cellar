import Foundation

/// How a service's status should read visually.
///
/// A semantic tone rather than a colour, because `BrewClient` is GUI-free: the
/// app target owns the mapping to an actual `Color`, exactly as it does for
/// `InstalledBadge`. `CaseIterable` so "every tone the projection produces is
/// one the surface knows how to draw" is a claim a test can make about the
/// whole set rather than about the cases someone remembered.
public enum ServiceStatusTone: Sendable, Equatable, Hashable, CaseIterable {
    /// Running now.
    case running
    /// Not running, and nothing is wrong with that.
    case idle
    /// Registered to run later.
    case scheduled
    /// brew is reporting it as broken.
    case failed
    /// brew reported something this build cannot interpret as either.
    case indeterminate
}

extension ServicesError {
    /// One line a consumer can render without inspecting acquisition internals,
    /// mirroring `InstalledInventoryError.shortDescription`.
    public var shortDescription: String {
        switch self {
        case .brewUnavailable:
            "brew could not be run."
        case .commandFailed(let status, let message):
            // brew's own words whenever it produced any: "the command failed"
            // tells the user nothing they can act on.
            message.isEmpty ? "brew exited with status \(status)." : message
        case .malformedPayload:
            "brew returned something Cellar could not read."
        case .cancelled:
            "The refresh was cancelled."
        }
    }
}

/// Why the services list is empty, when it is.
///
/// `ServicesLoadState` has five cases and the surface has one empty slot, so
/// something has to map one onto the other. Doing it in the view by testing
/// `absence != nil` collapses `idle`, `loading` and `failed` into a single
/// affirmative sentence — and "Homebrew is not managing any background services
/// on this Mac" is a confident factual claim that is false in all three. A
/// failed probe in particular would be reported to the user as an untroubled
/// empty success, with brew's reason discarded.
///
/// So the decision is a value, projected here where `swift test` reaches it,
/// exactly as `InstalledEmptyState` decides it exhaustively over all five of its
/// own cases. The app target still owns the symbols and the layout; it owns no
/// rule about which sentence is true.
public enum ServicesEmptyState: Sendable, Equatable {
    /// Nothing has been asked yet, or the answer has not arrived.
    case reading
    /// brew answered, and it is managing nothing. The only affirmative absence.
    case nothingManaged
    /// There is no usable brew to ask. Guidance, not failure (SM11).
    case brewAbsent(InstalledAbsence)
    /// The probe failed, carrying the reason it failed.
    case failed(String)

    /// The headline.
    public var title: String {
        switch self {
        case .reading: "Reading services"
        case .nothingManaged: "No services"
        case .brewAbsent(let absence): absence.title
        case .failed: "Could not read services"
        }
    }

    /// The sentence under it. Never empty: an empty slot with no explanation is
    /// the same failure in a quieter font.
    public var message: String {
        switch self {
        case .reading: "Asking brew which services it is managing."
        case .nothingManaged: "Homebrew is not managing any background services on this Mac."
        case .brewAbsent(let absence): absence.explanation
        case .failed(let reason): reason
        }
    }
}

extension ServicesLoadState {
    /// What an empty list means in this state.
    ///
    /// Exhaustive by construction over all five cases, so a sixth state could
    /// not be silently absorbed into "no services".
    public var emptyState: ServicesEmptyState {
        switch self {
        case .idle, .loading: .reading
        case .loaded: .nothingManaged
        case .brewAbsent(let absence): .brewAbsent(absence)
        case .failed(let error): .failed(error.shortDescription)
        }
    }
}

extension ServiceStatus {
    /// What the row says.
    ///
    /// The product's words for the seven brew publishes — `none` reads as
    /// "Not running", which is what it means — and, for an unrecognised value,
    /// **brew's own string**. Relabelling it as "Unknown" would collide with
    /// the real `unknown` status and report something brew never said; hiding
    /// the service would take it out of reach entirely.
    public var label: String {
        switch self {
        case .started: "Running"
        case .none: "Not running"
        case .scheduled: "Scheduled"
        case .stopped: "Stopped"
        case .error: "Error"
        case .unknown: "Unknown"
        case .other: "Other"
        case .unrecognised(let raw): raw
        }
    }

    /// How it should read visually.
    ///
    /// Only the two states brew reports as broken are `.failed`. An
    /// unrecognised status is `.indeterminate` and never red: colouring it as
    /// a failure would be this build's guess presented as brew's report.
    public var tone: ServiceStatusTone {
        switch self {
        case .started: .running
        case .none, .stopped: .idle
        case .scheduled: .scheduled
        case .error, .unknown: .failed
        case .other, .unrecognised: .indeterminate
        }
    }
}
