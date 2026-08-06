//
//  DiscoverSectionModels.swift
//  cellar
//

import Catalog
import Foundation

/// The row and section shapes Discover renders.
///
/// Plain `nonisolated` value types with no SwiftUI in them, so every rule worth
/// checking — one row per *resolved* entry, 1-based ranks, the metric label that
/// matches the kind, and an empty section that explains itself — is testable
/// without rendering anything. The views below them are then only layout.
///
/// The app target defaults to `MainActor` isolation, so `nonisolated` here is
/// load-bearing rather than decorative: it is what lets these be built and
/// asserted on from an ordinary test.

// MARK: - Ranked ladders

nonisolated struct DiscoverLadderRow: Identifiable, Hashable {
    var id: PackageID { package.id }

    let rank: Int
    let package: CatalogPackage
    let installs: InstallCount

    var name: String { package.name }
    var displayName: String { package.displayName }
    var desc: String? { package.desc }

    /// "installs on request" for a formula, "installs" for a cask. The two
    /// ladders measure different quantities, and one shared label would
    /// misreport whichever it did not describe.
    var metricLabel: String { installs.metricDescription }

    var installsLabel: String { installs.value.formatted(.number.grouping(.automatic)) }
}

nonisolated struct DiscoverLadderModel {
    let title: String
    let state: DiscoverSectionState<[RankedPackage]>

    var rows: [DiscoverLadderRow] {
        (state.content ?? []).map {
            DiscoverLadderRow(rank: $0.rank, package: $0.package, installs: $0.installs)
        }
    }

    var isEmpty: Bool { rows.isEmpty }

    /// Why this section has nothing, or `nil` when it has something. The copy
    /// comes from `CellarCore`; a view never invents a sentence.
    var explanation: String? { DiscoverSectionCopy.explanation(for: state) }
}

// MARK: - Curated

nonisolated struct DiscoverCuratedRow: Identifiable, Hashable {
    var id: PackageID { package.id }

    let package: CatalogPackage
    /// The curated list's words, never the package's own `desc`.
    let blurb: String

    var name: String { package.name }
    var displayName: String { package.displayName }
}

nonisolated struct DiscoverCuratedCategoryModel: Identifiable, Hashable {
    let id: String
    let title: String
    let rows: [DiscoverCuratedRow]
}

nonisolated struct DiscoverCuratedModel {
    let state: DiscoverSectionState<[ResolvedCuratedCategory]>

    /// One row per **resolved** entry only. An unresolvable token was already
    /// dropped and counted upstream, so nothing here can render a package the
    /// user could not install.
    var categories: [DiscoverCuratedCategoryModel] {
        (state.content ?? []).map { category in
            DiscoverCuratedCategoryModel(
                id: category.id,
                title: category.title,
                rows: category.entries.map {
                    DiscoverCuratedRow(package: $0.package, blurb: $0.blurb)
                }
            )
        }
    }

    var isEmpty: Bool { categories.isEmpty }

    var explanation: String? { DiscoverSectionCopy.explanation(for: state) }
}

// MARK: - New to you

nonisolated struct DiscoverArrivalRow: Identifiable, Hashable {
    var id: PackageID { package.id }

    let package: CatalogPackage
    /// When **this Mac** first saw it. Never presented as a publication date.
    let firstSeenAt: Date

    var name: String { package.name }
    var displayName: String { package.displayName }

    /// "3 days ago", reckoned from the instant the caller supplies.
    ///
    /// `RelativeDateTimeFormatter` rather than `.formatted(.relative(...))`
    /// because that style has no reference-date parameter and silently reads the
    /// wall clock — which would make `now` here decorative, and a clock seam
    /// that only pretends to be injected is worse than none.
    func firstSeenLabel(relativeTo now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: firstSeenAt, relativeTo: now)
    }
}

nonisolated struct DiscoverArrivalsModel {
    let state: DiscoverSectionState<[ArrivalRow]>
    let hiddenCount: Int

    var rows: [DiscoverArrivalRow] {
        (state.content ?? []).map {
            DiscoverArrivalRow(package: $0.package, firstSeenAt: $0.firstSeenAt)
        }
    }

    var isEmpty: Bool { rows.isEmpty }

    /// This section explains itself in **both** states, which is what separates
    /// it from the other two. Populated, the sentence says whose observation the
    /// dates are; empty, it says newness starts from this sync onward. Either
    /// way the words come from `CellarCore`, where a test owns them.
    var explanation: String? {
        if case .populated = state { return DiscoverCopy.arrivalsPopulated }
        return DiscoverSectionCopy.explanation(for: state)
    }

    var hiddenLabel: String? {
        hiddenCount > 0 ? "and \(hiddenCount) more" : nil
    }
}

// MARK: - Copy

nonisolated enum DiscoverSectionCopy {
    /// The sentence for a state, or `nil` when the section is populated.
    ///
    /// Every branch defers to `DiscoverCopy` in `CellarCore`. A view that wrote
    /// its own wording here is exactly how "new to you" would quietly become
    /// "new on Homebrew".
    static func explanation<Content>(for state: DiscoverSectionState<Content>) -> String? {
        switch state {
        case .populated: nil
        case .empty(let reason): DiscoverCopy.text(for: reason)
        case .awaitingCatalog: DiscoverCopy.awaitingCatalog
        }
    }
}
