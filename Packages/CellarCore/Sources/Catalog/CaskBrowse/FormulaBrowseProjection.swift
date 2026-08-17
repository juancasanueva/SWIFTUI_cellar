import Foundation

/// Builds `FormulaBrowseContent` from the snapshot already in memory —
/// `CaskBrowseProjection`'s rules re-applied to formulae, with the cask-mined
/// inputs (categories, added dates) deliberately absent rather than faked.
///
/// Pure and `nonisolated`, like its sibling: no request, no subprocess, no
/// sync triggered by a page being rendered.
public enum FormulaBrowseProjection {
    /// How many formulae the Most Popular shelf shows. Deeper than the cask
    /// shelves' eight on purpose: the cask Browse fills its page with many
    /// shelves, and this page has exactly one.
    public static let sectionSize = 24
    /// How many formulae the Featured page shows, the cask cap verbatim.
    public static let featuredSize = CaskBrowseProjection.featuredSize

    /// `content(...)` off the caller's actor — the `CaskBrowseProjection.build`
    /// idiom: sorting ~8k formulae per adoption stays off the main actor.
    @concurrent
    public static func build(snapshot: CatalogSnapshot?) async -> FormulaBrowseContent {
        content(snapshot: snapshot)
    }

    public nonisolated static func content(snapshot: CatalogSnapshot?) -> FormulaBrowseContent {
        // No usable snapshot: nothing has been measured yet.
        guard let snapshot else { return .empty }

        // Eligibility, the cask filter re-decided for formulae: live formulae
        // only, and no versioned aliases — `python@3.12` is a pin of the
        // mainline `python`, and a storefront that lists both ranks the same
        // software twice. The `font-` clause has no formula meaning and is
        // deliberately absent rather than copied.
        let formulae = snapshot.packages.filter { package in
            package.kind == .formula
                && !package.deprecated
                && !package.disabled
                && !package.name.contains("@")
        }
        guard !formulae.isEmpty else { return .empty }

        // Absent counts flatten to zero for this sort **only** — the packages
        // keep their `nil`, because "not reported" is not "zero installs".
        let popularityOrder = formulae.sorted {
            ($0.installCount365d ?? 0) > ($1.installCount365d ?? 0)
        }

        return FormulaBrowseContent(
            housePick: popularityOrder.first,
            mostPopular: Array(popularityOrder.prefix(sectionSize)),
            featured: Array(popularityOrder.prefix(featuredSize)),
            allByPopularity: popularityOrder,
            formulaCount: formulae.count
        )
    }
}
