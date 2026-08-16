import Foundation

/// The analytics windows the Top Charts page can rank by.
///
/// The raw value is the path segment Homebrew publishes the endpoint under
/// (`30d.json`, …), so a period names its own resource and nothing else has to
/// map one to the other.
public enum CaskChartsPeriod: String, CaseIterable, Sendable, Hashable {
    case days30 = "30d"
    case days90 = "90d"
    case days365 = "365d"

    /// The chip and menu label, CaskHub's spelling verbatim.
    public var label: String {
        switch self {
        case .days30: "30 Days"
        case .days90: "90 Days"
        case .days365: "365 Days"
        }
    }
}
