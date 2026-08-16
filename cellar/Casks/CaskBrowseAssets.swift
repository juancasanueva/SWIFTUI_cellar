//
//  CaskBrowseAssets.swift
//  cellar
//

import Catalog
import SwiftUI

/// The vendored category catalog, loaded once and read by every cask surface.
///
/// A store rather than a per-view `.task` result so the browse page, its cards,
/// and any later category page all read the *same* decode — the asset is ~400 KB
/// of JSON and decoding it once per card would be absurd.
@MainActor
@Observable
final class CaskBrowseAssets {
    /// `nil` until `load()` resolves, and forever after when the resource is
    /// missing or version-mismatched — the surfaces render without categories
    /// rather than failing.
    private(set) var catalog: CaskCategoryCatalog?

    /// Whether a load has been asked for, so a second appearing view joins the
    /// first load instead of decoding the asset again.
    private var hasStartedLoading = false

    /// Called from the browse view's `.task`; idempotent by design.
    func load() async {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        catalog = await CaskCategoryCatalog.shipped()
    }

    /// The display name of a token's primary category, or `nil` for an
    /// unmapped token — no default category, mirroring the mapping's own rule.
    func primaryCategoryName(for token: String) -> String? {
        guard let catalog, let mapping = catalog.tokenToCategory[token] else { return nil }
        return catalog.categories[mapping.primary]?.displayName
    }

    /// Whether the CaskFlow icons branch carries artwork for this token — the
    /// manifest gate `CaskIconURL.candidateURLs` asks about.
    func isKnownIconToken(_ token: String) -> Bool {
        catalog?.iconTokens.contains(token) ?? false
    }
}
