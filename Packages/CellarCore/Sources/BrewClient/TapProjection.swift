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

    /// The two official rows, in presentation order. One constant, so the list
    /// and the detail pane resolve a selected official source from the same
    /// values (tap-management TM4).
    public static let allOfficialSources = [
        OfficialTapSource(id: "homebrew/core", title: "Homebrew Core"),
        OfficialTapSource(id: "homebrew/cask", title: "Homebrew Cask")
    ]

    /// The official source a selection names, or `nil` for anything else —
    /// including a local `homebrew/core` checkout, which is still the official
    /// source and never a third-party tap to untap (TM4).
    public static func officialSource(named name: String?) -> OfficialTapSource? {
        guard let name else { return nil }
        return allOfficialSources.first { $0.id == name.lowercased() }
    }

    public init(inventory: TapInventory, isAvailable: Bool = true) {
        officialSources = Self.allOfficialSources
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

// MARK: - Per-package trust grants (package-trust PT3–PT8)

extension TapProjection {
    /// The exact copy a package row carries when Homebrew records a grant for
    /// that exact package. Positive-only: there is no counterpart for a package
    /// without one, because absence from the report is not a fact about trust
    /// (PT6 :334-339).
    public static let grantMarker = "Trusted individually"

    /// The per-tap count and the marked packages as **one** value, so the list
    /// row, the detail header and the detail package rows cannot disagree — the
    /// same one-projection rule the badge follows (PT5 :287-292, DD-6).
    public struct TapGrantPresentation: Sendable, Equatable {
        /// "2 trusted individually", or `nil` when nothing may be claimed: a
        /// report that does not exist, and a count of zero, both render no line
        /// at all (DD-7).
        public let countLine: String?
        /// Exactly the packages of this tap whose rows may show the marker.
        public let marked: Set<PackageID>

        public init(countLine: String?, marked: Set<PackageID>) {
            self.countLine = countLine
            self.marked = marked
        }
    }

    /// What this tap's row and header may say about individual grants.
    public static func grants(
        for tap: TapRecord,
        in state: TrustGrantState
    ) -> TapGrantPresentation {
        guard let ledger = state.ledger else {
            return TapGrantPresentation(countLine: nil, marked: [])
        }
        var marked: Set<PackageID> = []
        var count = 0
        for (entries, kind) in [
            (ledger.formulae, PackageKind.formula),
            (ledger.casks, PackageKind.cask)
        ] {
            for entry in entries {
                guard let id = attribute(entry, kind: kind, to: tap) else { continue }
                marked.insert(id)
                // Entries, not identities: the same qualified string can appear
                // in both namespaces, and those are two grants about two
                // packages (PT4 :254-260, measured).
                count += 1
            }
        }
        return TapGrantPresentation(
            countLine: count == 0 ? nil : "\(count) trusted individually",
            marked: marked
        )
    }

    /// Whether Homebrew records a grant for **this exact package**, resolved by
    /// kind, bare name and tap of origin together (PD8 :48-53).
    ///
    /// A bare name never matches a qualified entry, and where the tap of origin
    /// is not known exactly the answer is `false`. Both are the same rule: a
    /// grant for `acme/tools/widget` says nothing about anybody else's `widget`.
    public static func grantsIndividually(
        _ id: PackageID,
        publishedBy tap: String,
        in state: TrustGrantState
    ) -> Bool {
        guard let ledger = state.ledger else { return false }
        let entries = id.kind == .formula ? ledger.formulae : ledger.casks
        let prefix = tap + "/"
        return entries.contains {
            $0.hasPrefix(prefix) && bareToken($0, publishedBy: tap) == id.name
        }
    }

    /// Every decoded entry, in exactly one category, with the totals summing to
    /// what brew sent (PT4 :219-230).
    public static func accounting(
        of ledger: TrustGrantLedger,
        taps: [TapRecord]
    ) -> UnattributedGrants {
        var attributed = 0
        var unmatchedFormulae: [String] = []
        var unmatchedCasks: [String] = []
        for entry in ledger.formulae {
            if taps.contains(where: { attribute(entry, kind: .formula, to: $0) != nil }) {
                attributed += 1
            } else {
                unmatchedFormulae.append(entry)
            }
        }
        for entry in ledger.casks {
            if taps.contains(where: { attribute(entry, kind: .cask, to: $0) != nil }) {
                attributed += 1
            } else {
                unmatchedCasks.append(entry)
            }
        }

        // A `taps` entry names a **tap**, not a package. For an installed tap it
        // is that tap's own grant, which `tap-info` already answers for, so it is
        // excluded from every package count — stated here rather than dropped
        // (DD-9). For a tap that is gone it is an orphan, which survives an
        // untap and therefore has to be shown (PT8 :423-433).
        var excluded = 0
        var orphanTapGrants: [String] = []
        for entry in ledger.taps {
            if taps.contains(where: { $0.name == entry }) {
                excluded += 1
            } else {
                orphanTapGrants.append(entry)
            }
        }

        return UnattributedGrants(
            orphanTapGrants: orphanTapGrants,
            unmatchedFormulae: unmatchedFormulae,
            unmatchedCasks: unmatchedCasks,
            other: ledger.commands + ledger.unmodelled.keys.sorted()
                .flatMap { ledger.unmodelled[$0] ?? [] },
            attributed: attributed,
            excluded: excluded
        )
    }

    /// What the Taps surface's dedicated section shows for this report.
    public static func unattributedSection(
        in state: TrustGrantState,
        taps: [TapRecord]
    ) -> TrustGrantSection {
        switch state {
        case .unreported:
            return .unreported
        case .noGrants:
            return .noneRecorded
        case .granted(let ledger):
            let totals = accounting(of: ledger, taps: taps)
            return totals.isEmpty ? .nothingToShow : .unattributed(totals)
        }
    }

    /// The one attribution rule, expressed once and used by every caller
    /// (DD-5). **Both** conditions, always.
    ///
    /// Never a positional split: a real `formulae` entry is URL-shaped
    /// (`https://github.com/cloudmanic/spice-edit/spice-edit`, measured), so
    /// reading its first two slash-separated components as a tap yields
    /// something that is not a tap and was never published by one. Requiring the
    /// tap's own prefix *and* its own publication makes attribution
    /// single-candidate by construction, because tap names are unique.
    private static func attribute(
        _ entry: String,
        kind: PackageKind,
        to tap: TapRecord
    ) -> PackageID? {
        guard entry.hasPrefix(tap.name + "/") else { return nil }
        let id = PackageID(kind: kind, name: bareToken(entry, publishedBy: tap.name))
        return publishes(id, in: tap) ? id : nil
    }
}

/// The entries no installed tap publishes, plus the two counts that make the
/// partition checkable (PT4 :219-230).
///
/// Five categories rather than three. An orphan tap grant is neither a package
/// grant nor something Cellar may discard, and an excluded tap grant has to be
/// counted for "these totals sum to the entries decoded" to mean anything.
public struct UnattributedGrants: Sendable, Equatable {
    /// `taps` entries naming a tap this Mac does not have installed.
    public let orphanTapGrants: [String]
    /// `formulae` entries no installed tap publishes.
    public let unmatchedFormulae: [String]
    /// `casks` entries no installed tap publishes.
    public let unmatchedCasks: [String]
    /// Every `commands` entry, and every entry from a namespace this capability
    /// does not model. Named "other" in copy (DD-9).
    public let other: [String]
    /// Entries attributed to an installed tap.
    public let attributed: Int
    /// `taps` entries for taps that **are** installed: tap grants, excluded from
    /// every package count by a stated rule rather than by omission.
    public let excluded: Int

    public init(
        orphanTapGrants: [String],
        unmatchedFormulae: [String],
        unmatchedCasks: [String],
        other: [String],
        attributed: Int,
        excluded: Int
    ) {
        self.orphanTapGrants = orphanTapGrants
        self.unmatchedFormulae = unmatchedFormulae
        self.unmatchedCasks = unmatchedCasks
        self.other = other
        self.attributed = attributed
        self.excluded = excluded
    }

    public var unmatchedCount: Int { unmatchedFormulae.count + unmatchedCasks.count }
    /// Everything this section actually shows.
    public var surfacedCount: Int { orphanTapGrants.count + unmatchedCount + other.count }
    /// The whole decoded set. Equal to the ledger's entry count, by construction.
    public var total: Int { attributed + excluded + surfacedCount }
    public var isEmpty: Bool { surfacedCount == 0 }
}

/// What the Taps surface's "Other trusted packages" section renders.
///
/// The three empty-ish cases are three different facts, and the copy says which
/// (PT6 :366-373): brew did not answer; brew answered and recorded nothing; brew
/// answered and everything it recorded belongs to a tap already on screen.
public enum TrustGrantSection: Sendable, Equatable {
    /// No report exists. One sentence, no totals.
    case unreported
    /// A report exists and carries no entry at all.
    case noneRecorded
    /// A report exists and every entry is already accounted to a tap on screen.
    case nothingToShow
    case unattributed(UnattributedGrants)

    public struct Group: Sendable, Equatable, Identifiable {
        public var id: String { title }
        public let title: String
        public let entries: [String]

        public init(title: String, entries: [String]) {
            self.title = title
            self.entries = entries
        }
    }

    public var title: String { "Other trusted packages" }

    /// The one sentence this section states, or `nil` when it has nothing to
    /// say. Exposed as a value so the view renders copy it never composes.
    public var sentence: String? {
        switch self {
        case .unreported:
            "This Homebrew does not report per-package trust."
        case .noneRecorded:
            "Homebrew records no packages trusted individually."
        case .nothingToShow:
            nil
        case .unattributed(let grants):
            // Stated plainly, because a per-package grant survives an untap and
            // a later re-tap re-arms it. Cellar shows that; it does not close it.
            grants.orphanTapGrants.isEmpty
                ? nil
                : "Homebrew still records these grants. Cellar shows them; it does not remove them."
        }
    }

    /// The listed entries, grouped, with empty groups omitted rather than
    /// rendered.
    public var groups: [Group] {
        guard case .unattributed(let grants) = self else { return [] }
        return [
            Group(title: "Taps that are no longer installed", entries: grants.orphanTapGrants),
            Group(title: "Formulae", entries: grants.unmatchedFormulae),
            Group(title: "Casks", entries: grants.unmatchedCasks),
            Group(title: "Other", entries: grants.other)
        ].filter { !$0.entries.isEmpty }
    }
}
