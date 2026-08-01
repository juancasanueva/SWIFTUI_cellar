import Foundation

/// A status worth badging in a list row.
public enum PackageStatusBadge: String, Sendable, Hashable, CaseIterable {
    case deprecated
    case disabled

    public var label: String {
        switch self {
        case .deprecated: "Deprecated"
        case .disabled: "Disabled"
        }
    }

    public var systemImage: String {
        switch self {
        case .deprecated: "exclamationmark.triangle"
        case .disabled: "nosign"
        }
    }
}

extension CatalogPackage {
    /// The statuses a row should badge, in severity order.
    ///
    /// Deprecated and disabled are independent: a package can be both, and a
    /// deprecated package is still installable, so neither removes it from the
    /// catalog (package-search PS4, package-detail PD4).
    public var badges: [PackageStatusBadge] {
        var badges: [PackageStatusBadge] = []
        if deprecated { badges.append(.deprecated) }
        if disabled { badges.append(.disabled) }
        return badges
    }

    /// The install count as a row should show it.
    ///
    /// "not reported" rather than "0": the catalog knows the difference and the
    /// UI must not flatten it (package-detail PD5).
    public var installCountDescription: String {
        guard let installCount else { return "not reported" }
        return installCount.value.formatted(.number.grouping(.automatic))
    }
}

extension InstallCount {
    public var metricDescription: String {
        switch metric {
        case .installsOnRequest: "installs on request"
        case .installs: "installs"
        }
    }

    public var windowDescription: String { "last \(windowDays) days" }

    /// The sentence that stops the number from reading as an install total.
    public var lowerBoundNote: String {
        "A lower bound: counts only Homebrew users who have not opted out of analytics."
    }
}

extension PackageDependency {
    /// Why this entry is not a link, or `nil` when it is.
    public var resolutionNote: String? {
        isResolvable ? nil : "not in catalog"
    }
}

extension CatalogSyncStatus {
    /// One line a consumer can render without inspecting transport internals
    /// (catalog-sync CS8).
    public var shortDescription: String {
        switch self {
        case .idle, .succeeded: "Up to date"
        case .downloading: "Downloading catalog…"
        case .decoding: "Reading catalog…"
        case .failed(let error): "Catalog update failed: \(error.shortDescription)"
        }
    }

    /// Whether the UI should show a spinner.
    public var isBusy: Bool {
        switch self {
        case .downloading, .decoding: true
        case .idle, .succeeded, .failed: false
        }
    }
}

extension CatalogSyncError {
    public var shortDescription: String {
        switch self {
        case .offline: "no network connection"
        case .httpStatus(let status): "the server replied \(status)"
        case .malformedPayload: "the published catalog could not be read"
        case .persistence: "the catalog could not be saved"
        case .cancelled: "the update was cancelled"
        }
    }
}
