import Catalog
import Foundation

public struct OfficialTapSource: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let explanation: String
    public let isMutable: Bool

    public init(id: String, title: String) {
        self.id = id
        self.title = title
        explanation = "API-backed; no local tap required"
        isMutable = false
    }
}

public struct TapPackage: Sendable, Equatable, Identifiable {
    public let id: PackageID
    public let publishedName: String
    public let displayName: String
    public let installedHandoff: PackageID?

    public var isInstalled: Bool { installedHandoff != nil }
    public var uninstalledExplanation: String? {
        isInstalled ? nil : "Not installed."
    }

    public init(
        id: PackageID,
        publishedName: String,
        displayName: String,
        installedHandoff: PackageID?
    ) {
        self.id = id
        self.publishedName = publishedName
        self.displayName = displayName
        self.installedHandoff = installedHandoff
    }
}

public enum TapPresentationState: Sendable, Equatable {
    case idle
    case loading(hasLastGood: Bool)
    case content(isThirdPartyEmpty: Bool)
    case unavailable(InstalledAbsence)
    case error(TapInventoryError, hasLastGood: Bool)
}

public struct TapProjection: Sendable, Equatable {
    public static let officialNames: Set<String> = ["homebrew/core", "homebrew/cask"]

    public let officialSources: [OfficialTapSource]
    public let thirdPartyTaps: [TapRecord]
    public let canAddTap: Bool

    public init(inventory: TapInventory, isAvailable: Bool = true) {
        officialSources = [
            OfficialTapSource(id: "homebrew/core", title: "Homebrew Core"),
            OfficialTapSource(id: "homebrew/cask", title: "Homebrew Cask")
        ]
        thirdPartyTaps = inventory.taps.filter { !Self.officialNames.contains($0.name.lowercased()) }
        canAddTap = isAvailable
    }

    /// Badge and controls as **one** value, so the three facts cannot disagree
    /// and the list row, the detail header and the tests all read the same
    /// projection (tap-management TM12).
    public struct TapTrustPresentation: Sendable, Equatable {
        /// The badge text, or `nil` when nothing may be claimed.
        public let badge: String?
        /// Whether the **Trust** control is offered.
        public let canGrant: Bool
        /// Whether the **Untrust** control is offered.
        public let canRevoke: Bool

        public init(badge: String?, canGrant: Bool, canRevoke: Bool) {
            self.badge = badge
            self.canGrant = canGrant
            self.canRevoke = canRevoke
        }
    }

    /// The one projection both tap surfaces consume.
    ///
    /// Every string here is about the **tap**. A per-package grant is
    /// independent of a tap grant and can make a package loadable while its tap
    /// is untrusted, so copy claiming a *package* is untrusted would be false
    /// (TM12; design R7).
    public static func trust(for tap: TapRecord) -> TapTrustPresentation {
        switch tap.trust {
        case .untrusted:
            TapTrustPresentation(badge: "Untrusted", canGrant: true, canRevoke: false)
        case .trusted:
            TapTrustPresentation(badge: nil, canGrant: false, canRevoke: true)
        // A Homebrew that reports nothing gets no badge and neither control, and
        // neither control ever builds or spawns a process for it.
        case .unreported:
            TapTrustPresentation(badge: nil, canGrant: false, canRevoke: false)
        }
    }

    public static func packages(
        for tap: TapRecord,
        installed: InstalledInventory
    ) -> [TapPackage] {
        let prefix = tap.name + "/"
        let formulae = tap.formulaNames.map { published -> TapPackage in
            let display = published.hasPrefix(prefix)
                ? String(published.dropFirst(prefix.count))
                : published
            let id = PackageID(kind: .formula, name: display)
            return TapPackage(
                id: id,
                publishedName: published,
                displayName: display,
                installedHandoff: exactInstalled(id, tap: tap.name, inventory: installed)
            )
        }
        // `brew tap-info --json` publishes cask tokens fully qualified, exactly
        // as it publishes formula names, while the installed snapshot keys a
        // cask by the bare token brew installs by. Same prefix rule for both.
        let casks = tap.caskTokens.map { published -> TapPackage in
            let token = published.hasPrefix(prefix)
                ? String(published.dropFirst(prefix.count))
                : published
            let id = PackageID(kind: .cask, name: token)
            return TapPackage(
                id: id,
                publishedName: published,
                displayName: token,
                installedHandoff: exactInstalled(id, tap: tap.name, inventory: installed)
            )
        }
        return formulae + casks
    }

    /// The design's count line — "5 formulae · 1 cask" — with zero components
    /// omitted rather than rendered, and emptiness named outright.
    public static func packageSummary(for tap: TapRecord) -> String {
        let formulae = tap.formulaNames.count
        let casks = tap.caskTokens.count
        let components = [
            formulae > 0 ? "\(formulae) formula\(formulae == 1 ? "" : "e")" : nil,
            casks > 0 ? "\(casks) cask\(casks == 1 ? "" : "s")" : nil
        ].compactMap(\.self)
        return components.isEmpty ? "No packages" : components.joined(separator: " · ")
    }

    public static func filter(
        _ packages: [TapPackage],
        query: String,
        kind: PackageKind?
    ) -> [TapPackage] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return packages.filter { package in
            (kind == nil || package.id.kind == kind)
                && (normalized.isEmpty || package.displayName.localizedCaseInsensitiveContains(normalized))
        }
    }

    public static func state(
        loadState: TapLoadState,
        inventory: TapInventory
    ) -> TapPresentationState {
        switch loadState {
        case .idle: .idle
        case .loading: .loading(hasLastGood: !inventory.taps.isEmpty)
        case .loaded:
            .content(isThirdPartyEmpty: inventory.taps.allSatisfy {
                officialNames.contains($0.name.lowercased())
            })
        case .brewAbsent(let absence): .unavailable(absence)
        case .failed(let error): .error(error, hasLastGood: !inventory.taps.isEmpty)
        }
    }

    private static func exactInstalled(
        _ id: PackageID,
        tap: String,
        inventory: InstalledInventory
    ) -> PackageID? {
        inventory.packages.first { $0.id == id && $0.tap == tap }?.id
    }
}
