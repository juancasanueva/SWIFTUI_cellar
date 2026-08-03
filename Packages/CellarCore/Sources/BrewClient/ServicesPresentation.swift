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
