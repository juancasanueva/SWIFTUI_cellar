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

extension ServiceDetailFailure {
    /// One line a consumer can render without inspecting probe internals.
    ///
    /// The two refusals that never reached brew say so in Cellar's own voice:
    /// attributing them to brew would report something brew never said.
    public var shortDescription: String {
        switch self {
        case .probe(let error): error.shortDescription
        case .unusableName:
            "This service's name cannot be passed to brew safely, so Cellar did not ask about it."
        case .noInstallation: "Cellar has not located a Homebrew installation to ask."
        }
    }
}

/// What the detail pane says when it has no detail to show.
///
/// The detail pane's twin of `ServicesEmptyState`, and it exists for the same
/// reason: `ServiceDetailLoadState` has four cases and a pane branching on
/// `detail != nil` has two slots, so a probe that **failed** was rendered as
/// "No service selected" — a reassuring absence in place of a failure, with
/// brew's reason discarded. Nothing selected, reading and failed are three
/// different facts and each gets its own sentence.
public enum ServiceDetailNotice: Sendable, Equatable {
    /// Nothing is selected. The only genuine absence.
    case nothingSelected
    /// A probe for this service has not answered yet.
    case reading(String)
    /// The probe failed, carrying the service and the reason it failed.
    case failed(service: String, reason: String)

    /// The headline.
    public var title: String {
        switch self {
        case .nothingSelected: "No service selected"
        case .reading(let service): "Reading \(service)"
        case .failed(let service, _): "Could not read \(service)"
        }
    }

    /// The sentence under it. Never empty: an empty pane with no explanation is
    /// the same failure in a quieter font.
    public var message: String {
        switch self {
        case .nothingSelected:
            "Select a service to see where it is installed and what it logs."
        case .reading(let service): "Asking brew what it knows about \(service)."
        case .failed(_, let reason): reason
        }
    }
}

/// What the detail pane shows: brew's answer, or why there is not one.
public enum ServiceDetailPane: Sendable, Equatable {
    /// brew answered about the selected service.
    case detail(ServiceDetail)
    /// There is no answer to show, and this is why.
    case notice(ServiceDetailNotice)
}

extension ServiceDetailLoadState {
    /// What the detail pane shows in this state.
    ///
    /// Exhaustive by construction over all four cases, so a fifth could not be
    /// silently absorbed into "No service selected". The app target owns the
    /// symbols and the layout; it owns no rule about which sentence is true.
    public var pane: ServiceDetailPane {
        switch self {
        case .idle: .notice(.nothingSelected)
        case .loading(let name): .notice(.reading(name))
        case .loaded(let detail): .detail(detail)
        case .failed(let name, let reason):
            .notice(.failed(service: name, reason: reason.shortDescription))
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
