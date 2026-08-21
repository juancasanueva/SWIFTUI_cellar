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
///    makes ordering a guess and inequality a fact. Self-updating casks are
///    excluded: they legitimately run ahead of both catalogs. A package the
///    catalog cannot answer for contributes nothing.
/// 2. **Fetch-marker age**, only when not one package could be compared. The
///    threshold is the health score's own freshness bound rather than a second
///    constant that could drift from it. A non-answer reading — absent,
///    unreadable, future-dated, or never read — is not evidence: the card must
///    never appear on the strength of a question that was not answered.
nonisolated enum HomebrewUpdateNeed {
    /// - Parameter catalogVersion: the synced catalog's published version for
    ///   a package, or `nil` when the catalog has no answer for it.
    static func isBehind(
        packages: [InstalledPackage],
        catalogVersion: (PackageID) -> String?,
        lastUpdate: HomebrewLastUpdate?,
        now: Date,
        staleAfter: TimeInterval = HealthThresholds.lastUpdateFreshSeconds
    ) -> Bool {
        var compared = false
        for package in packages {
            if package.kind == .cask, package.isSelfUpdating { continue }
            guard let published = catalogVersion(package.id) else { continue }
            compared = true
            if published != package.catalogVersion { return true }
        }
        // The primary signal answered: every comparable package agrees, and a
        // stale marker must not overrule an observation.
        if compared { return false }

        guard let age = lastUpdate?.age(at: now) else { return false }
        return age > staleAfter
    }
}
