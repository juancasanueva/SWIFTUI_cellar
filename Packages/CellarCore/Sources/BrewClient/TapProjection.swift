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
        isInstalled ? nil : "Not in Cellar’s core/cask catalog."
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
        let casks = tap.caskTokens.map { token -> TapPackage in
            let id = PackageID(kind: .cask, name: token)
            return TapPackage(
                id: id,
                publishedName: token,
                displayName: token,
                installedHandoff: exactInstalled(id, tap: tap.name, inventory: installed)
            )
        }
        return formulae + casks
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
