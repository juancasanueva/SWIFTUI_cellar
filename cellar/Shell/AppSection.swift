//
//  AppSection.swift
//  cellar
//

import SwiftUI

/// The top-level places the sidebar can take you.
///
/// An enum rather than free-floating `NavigationLink`s so the sidebar selection
/// is a value the shell can hold, restore and switch over exhaustively.
enum AppSection: String, CaseIterable, Hashable, Identifiable {
    case home
    /// **Home remains its own section, and now takes the landing.** D4 settled
    /// the slice-5 half of the question: Health is its own section, Home is not
    /// folded into it, and Health did not take the landing spot. The landing
    /// itself was `.browse` from M1 until the design port, when the maintainer
    /// moved it to `.home` (2026-08-07) — the design document opens on Home,
    /// and by then Home carried the attention cards and snapshot that make a
    /// landing worth having. The history is recorded here rather than removed,
    /// because a deleted question is indistinguishable from one that was never
    /// asked.
    ///
    /// A `discover` case used to sit here — ranked ladders, a curated list,
    /// and this Mac's first observations. The maintainer retired it
    /// (2026-08-17) once the Discover Casks and Discover Formulae groups
    /// covered its job with live analytics rather than a static curated list.
    case browse
    /// Packages published by the taps this Mac has installed, searched on their
    /// own surface.
    ///
    /// Beside `.browse` in Overview rather than under Manage: it is the
    /// counterpart to Search catalog, and filing a *search* surface under *tap
    /// administration* is the boundary `tap-management` TM11 draws (DD-14).
    case tapSearch
    /// The CaskHub-style cask storefront: a house pick, curated shelves, and a
    /// grid of app cards. Its own group in the sidebar because it browses one
    /// kind of package by category rather than the whole catalog by query.
    case caskBrowse
    /// A hand-picked set of casks worth showing off. Placeholder page until the
    /// featured roster ships.
    case caskFeatured
    /// Every eligible cask ranked by install count. Placeholder page until the
    /// full ranked list ships.
    case caskTopCharts
    /// The casks this catalog has seen arrive most recently. Placeholder page
    /// until the added-dates ledger reaches the app.
    case caskRecentlyAdded
    /// One case standing for every category page: *which* category is showing
    /// is data the shell holds beside the section, not a case of this enum —
    /// eighteen cases for eighteen rows of vendored JSON would put the asset's
    /// contents into the type. Originally absent from `sidebarGroups`, reached
    /// only through data-driven sidebar rows; the maintainer retired those rows
    /// (2026-08-17) for the vertical space they cost, so the section now holds
    /// a static "Categories" row that opens a list-and-detail arrangement —
    /// categories in the list pane, the selected category's page in the detail.
    /// Cards' category labels and each shelf's View All still land here too.
    case caskCategory
    /// The formula storefront: the cask Browse's rules on the other kind. No
    /// Recently Added and no Categories siblings, because both lean on
    /// cask-mined data — added dates and the category map — that has no
    /// formula equivalent.
    case formulaBrowse
    /// The top hundred formulae by annual installs-on-request.
    case formulaFeatured
    /// Every eligible formula ranked by one analytics window's installs.
    case formulaTopCharts
    case installed
    /// The favorited slice of Installed, promoted to a place of its own by the
    /// design document. The filter chip on Installed remains; this is the same
    /// lens with a sidebar row, not a second source of truth.
    case favorites
    /// The outdated slice of Installed, likewise promoted by the design so the
    /// sidebar can carry the count that most often brings a user here.
    case updates
    /// Homebrew source inventory and third-party tap management.
    case taps
    /// The background services Homebrew manages.
    ///
    /// Its own place rather than a lens on Installed: a service is its own
    /// entity, not a field of a package, and one whose name matches an
    /// installed formula is still not that formula (service-management SM12).
    case services
    /// Read-only package, version, and cache storage visibility.
    case cleanup
    /// One number over eight signals, and everything it could not answer.
    ///
    /// Between Cleanup and Security — which is what PRD §5's "between Services
    /// and Security" asks for — and adjacent to Cleanup on purpose: three of its
    /// seven rows remediate through verbs Cleanup already ships, so the section a
    /// user is sent to is the one next door rather than three places away.
    case health
    /// Advisory coverage, CVE findings, and artifact integrity.
    ///
    /// Between Cleanup and History because it is read-only visibility over what
    /// is installed, like Cleanup, rather than a record of what Cellar did.
    case security
    /// The Brewfile surface: current state, export, and import. Previously
    /// reached through sheets on Taps; the design gives it a sidebar row.
    case brewfile
    /// The durable record of every mutation Cellar performed.
    ///
    /// Favorites was originally a filter chip only (settled Q4); the design
    /// document promotes the same lens to a sidebar row, and the chip stays.
    case history
    /// The app's own preferences — accent colour first among them.
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .browse: "Search"
        case .tapSearch: "Search taps"
        case .caskBrowse: "Browse"
        case .caskFeatured: "Featured"
        case .caskTopCharts: "Top Charts"
        case .caskRecentlyAdded: "Recently Added"
        // The list-pane header and the capsule bar's fallback; the bar shows
        // the selected category's display name whenever one is resolved.
        case .caskCategory: "Categories"
        case .formulaBrowse: "Browse"
        case .formulaFeatured: "Featured"
        case .formulaTopCharts: "Top Charts"
        case .installed: "Installed"
        case .favorites: "Favorites"
        case .updates: "Updates"
        case .taps: "Taps"
        case .services: "Services"
        case .cleanup: "Cleanup"
        case .health: "Health"
        case .security: "Security"
        case .brewfile: "Brewfile"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    /// The sidebar's wording, where the design writes a longer label than the
    /// toolbar's.
    var sidebarTitle: String {
        switch self {
        case .browse: "Search catalog"
        case .tapSearch: "Search our taps"
        // Exhaustive rather than `default:`, and deliberately so. A one-case
        // switch is not recognised as an `AppSection` switch by the placement
        // suite's detector; a second wording brings this one into its scope,
        // and the rule it enforces there — no `default:` — is the right rule:
        // a `default:` is what would let a new section ship with the toolbar's
        // wording in the sidebar without anyone deciding that.
        case .health, .home, .caskBrowse, .caskFeatured, .caskTopCharts,
             .caskRecentlyAdded, .caskCategory, .formulaBrowse, .formulaFeatured,
             .formulaTopCharts, .installed, .favorites, .updates, .taps, .services,
             .cleanup, .security, .brewfile, .history, .settings:
            title
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .browse: "magnifyingglass"
        // Verified against this SDK before use, like the calendar variant
        // below: a plausible symbol name that does not exist renders nothing.
        case .tapSearch: "sparkle.magnifyingglass"
        case .caskBrowse: "square.grid.2x2"
        case .caskFeatured: "star"
        case .caskTopCharts: "chart.line.uptrend.xyaxis"
        // `clock.badge.plus` does not exist in this SDK's SF Symbols; the
        // calendar variant is the verified nearest match.
        case .caskRecentlyAdded: "calendar.badge.plus"
        case .caskCategory: "square.grid.3x3"
        case .formulaBrowse: "terminal"
        case .formulaFeatured: "star"
        case .formulaTopCharts: "chart.line.uptrend.xyaxis"
        case .installed: "shippingbox"
        case .favorites: "heart"
        case .updates: "arrow.up.circle"
        case .taps: "externaldrive.connected.to.line.below"
        case .services: "gearshape"
        case .cleanup: "cabinet"
        case .health: "waveform.path.ecg"
        case .security: "shield"
        case .brewfile: "doc.text"
        case .history: "clock"
        case .settings: "gearshape.fill"
        }
    }

    // MARK: - Sidebar arrangement

    /// The design's four labelled groups, in its order. `settings` is not in
    /// any group: it lives in the sidebar's footer.
    static let sidebarGroups: [(title: String, sections: [AppSection])] = [
        ("Overview", [.home, .browse, .tapSearch]),
        ("Discover Casks", [.caskBrowse, .caskFeatured, .caskTopCharts, .caskRecentlyAdded, .caskCategory]),
        ("Discover Formulae", [.formulaBrowse, .formulaFeatured, .formulaTopCharts]),
        ("Packages", [.installed, .favorites, .updates, .services]),
        ("Insights", [.health, .security, .cleanup]),
        ("Manage", [.taps, .brewfile, .history]),
    ]

    static let sidebarFooter: [AppSection] = [.settings]
}
