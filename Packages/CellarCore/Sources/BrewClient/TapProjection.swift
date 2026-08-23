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

/// Whether this tap's package is installed on this Mac — and, when it is, how
/// much of that Homebrew is willing to say.
///
/// Three values rather than two because the middle one **is** installed
/// (tap-management TM5 :53-67). Collapsing it into "not installed" is what made
/// the shipped projection state something false about this Mac whenever a tap
/// was untrusted.
public enum TapPackageInstallState: Sendable, Equatable {
    case installed(PackageID)
    /// Installed, and Homebrew is withholding the tap that published it.
    case installedTapWithheld(PackageID)
    case notInstalled
}

public struct TapPackage: Sendable, Equatable, Identifiable {
    public let id: PackageID
    public let publishedName: String
    public let displayName: String
    public let state: TapPackageInstallState

    public var isInstalled: Bool { state != .notInstalled }

    /// **Show in Installed** is offered in *both* installed states: the handoff
    /// selects by exact `PackageID`, and that identity is exact regardless of
    /// what brew withholds (TM5 :62-63).
    public var installedHandoff: PackageID? {
        switch state {
        case .installed(let id), .installedTapWithheld(let id): id
        case .notInstalled: nil
        }
    }

    /// What the row says about installation — named for the question it answers
    /// now that one of its answers is "installed" (DD-10).
    public var statusExplanation: String? {
        switch state {
        case .installed: nil
        case .installedTapWithheld: "Installed. Homebrew withholds its tap while this tap is untrusted."
        case .notInstalled: "Not installed."
        }
    }

    public init(
        id: PackageID,
        publishedName: String,
        displayName: String,
        state: TapPackageInstallState
    ) {
        self.id = id
        self.publishedName = publishedName
        self.displayName = displayName
        self.state = state
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
        let formulae = tap.formulaNames.map { published -> TapPackage in
            let display = bareToken(published, publishedBy: tap.name)
            let id = PackageID(kind: .formula, name: display)
            return TapPackage(
                id: id,
                publishedName: published,
                displayName: display,
                state: installState(id, tap: tap, inventory: installed)
            )
        }
        // `brew tap-info --json` publishes cask tokens fully qualified, exactly
        // as it publishes formula names, while the installed snapshot keys a
        // cask by the bare token brew installs by. Same prefix rule for both.
        let casks = tap.caskTokens.map { published -> TapPackage in
            let token = bareToken(published, publishedBy: tap.name)
            let id = PackageID(kind: .cask, name: token)
            return TapPackage(
                id: id,
                publishedName: published,
                displayName: token,
                state: installState(id, tap: tap, inventory: installed)
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

    /// The bare token brew installs by, with only the **selected** tap's own
    /// `owner/repo/` prefix removed and no other prefix or substring touched
    /// (TM5 :46-51). One normalization, used by every caller, so they cannot
    /// drift apart.
    static func bareToken(_ published: String, publishedBy tap: String) -> String {
        let prefix = tap + "/"
        return published.hasPrefix(prefix) ? String(published.dropFirst(prefix.count)) : published
    }

    /// Whether this tap's own published set contains that exact `(kind, name)`.
    ///
    /// The tap's published names are the only source; nothing else may claim a
    /// package (TM5 :122-128). The inventory path satisfies this clause by
    /// construction — `packages(for:installed:)` iterates these very lists — and
    /// this is the same rule made callable for the refusal recovery (DD-7).
    public static func publishes(_ id: PackageID, in tap: TapRecord) -> Bool {
        let published = id.kind == .formula ? tap.formulaNames : tap.caskTokens
        return published.contains { bareToken($0, publishedBy: tap.name) == id.name }
    }

    /// Which of the three installed states this tap's package is in.
    ///
    /// The middle state is deliberately narrow: it requires **this** tap to be
    /// the one being withheld for, and — by construction, because the caller
    /// iterates this tap's own published names — the package to be one this tap
    /// publishes. A record with no tap under a trusted or unreported tap is not
    /// this tap's package, and claiming it would be the same false statement in
    /// the other direction (TM5 :113-137).
    private static func installState(
        _ id: PackageID,
        tap: TapRecord,
        inventory: InstalledInventory
    ) -> TapPackageInstallState {
        if inventory.packages.contains(where: { $0.id == id && $0.tap == tap.name }) {
            return .installed(id)
        }
        if tap.trust == .untrusted,
           inventory.packages.contains(where: { $0.id == id && $0.tap == nil }) {
            return .installedTapWithheld(id)
        }
        return .notInstalled
    }
}
