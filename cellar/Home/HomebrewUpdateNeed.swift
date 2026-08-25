//
//  HomebrewUpdateNeed.swift
//  cellar
//

import BrewClient
import Catalog
import DiskUsage
import Foundation

/// Whether the local Homebrew demonstrably lags what is published — the rule
/// behind the Home page's Update Homebrew card.
///
/// A pure function over values the shell already holds, so the claim is
/// provable without rendering (the `HealthComposition` idiom). Two signals, in
/// strict order:
///
/// 1. **Version disagreement.** The local brew's offered version
///    (`InstalledPackage.catalogVersion`, from `brew info --installed`) against
///    the synced catalog's published one (formulae.brew.sh). Both sides are the
///    same schema's stable field, so *any* difference is evidence the local
///    data is behind — no version-string ordering is ever attempted, because
///    Homebrew's version grammar (revisions, rebuilds, epoch-less schemes)
///    makes ordering a guess and inequality a fact. Only packages the synced
///    catalog actually publishes may testify: formulae from `homebrew/core`
///    and casks from `homebrew/cask`. A third-party tap's package can collide
///    with an unrelated core package of the same name — `hunk` from
///    modem-dev/tap against core's own `hunk` is the live case — and no
///    `brew update` can ever reconcile that pair, so it is excluded the same
///    way a self-updating cask is. A package the catalog cannot answer for
///    contributes nothing.
///
///    The comparison is only valid **in one direction**: the catalog snapshot
///    must have been downloaded at least as recently as brew's own fetch
///    marker. When brew fetched *after* the snapshot, a disagreement may mean
///    the snapshot is behind — reading it as "brew is behind" is backwards —
///    so those disagreements contribute nothing until the next catalog sync
///    resolves them. A non-answer marker cannot invalidate the snapshot.
/// 2. **Fetch-marker age**, only when not one package could be compared. The
///    threshold is the health score's own freshness bound rather than a second
///    constant that could drift from it. A non-answer reading — absent,
///    unreadable, future-dated, or never read — is not evidence: the card must
///    never appear on the strength of a question that was not answered.
nonisolated enum HomebrewUpdateNeed {
    /// What the Home page's Update Homebrew card says.
    ///
    /// The card is always on the page — `brew update` is the only way to
    /// learn whether brew is behind, so an affordance gated on that evidence
    /// would hide the very action that produces it. `isBehind` therefore
    /// chooses the wording and the emphasis, never the card's existence.
    struct Copy: Equatable {
        let title: String
        let sub: String
        /// Whether the evidence warrants the accent dress over the neutral one.
        let isEmphasized: Bool
    }

    static func copy(behind: Bool) -> Copy {
        if behind {
            return Copy(
                title: "Homebrew is behind what's published",
                sub: "Run brew update to refresh available versions and taps · installs nothing",
                isEmphasized: true
            )
        }
        return Copy(
            title: "Homebrew learns about new versions from brew update",
            sub: "Refreshes available versions and taps · installs nothing",
            isEmphasized: false
        )
    }

    /// - Parameters:
    ///   - catalogVersion: the synced catalog's published version for a
    ///     package, or `nil` when the catalog has no answer for it.
    ///   - catalogDownloadedAt: when the snapshot behind `catalogVersion` was
    ///     fetched, or `nil` when no snapshot is adopted.
    static func isBehind(
        packages: [InstalledPackage],
        catalogVersion: (PackageID) -> String?,
        catalogDownloadedAt: Date?,
        lastUpdate: HomebrewLastUpdate?,
        now: Date,
        staleAfter: TimeInterval = HealthThresholds.lastUpdateFreshSeconds
    ) -> Bool {
        // Brew fetched after the snapshot was downloaded, so a disagreement
        // cannot say which side is behind. Comparisons still *count* as
        // answered — the catalog has data, so the age fallback stays out —
        // but their disagreements are worthless until the next sync.
        let snapshotIsCurrent: Bool = {
            guard let marker = lastUpdate?.date, let downloaded = catalogDownloadedAt
            else { return true }
            return downloaded >= marker
        }()

        var compared = false
        for package in packages where Self.isComparable(package) {
            guard let published = catalogVersion(package.id) else { continue }
            compared = true
            if snapshotIsCurrent, published != package.catalogVersion { return true }
        }
        // The primary signal had data: agreement — or a disagreement it is not
        // entitled to read — and a stale marker must not overrule it.
        if compared { return false }

        guard let age = lastUpdate?.age(at: now) else { return false }
        return age > staleAfter
    }

    /// Whether the synced catalog can testify about this package at all.
    private static func isComparable(_ package: InstalledPackage) -> Bool {
        switch package.kind {
        case .formula: package.tap == "homebrew/core"
        case .cask: package.tap == "homebrew/cask" && !package.isSelfUpdating
        }
    }
}
