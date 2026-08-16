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
    /// Ranked ladders, a hand-picked list, and what this Mac has seen for the
    /// first time recently.
    ///
    /// Between Home and Browse because it serves the user *before* they have a
    /// query: Browse is a search field over ~16k records and answers nothing
    /// useful when empty.
    ///
    /// **Home remains its own section, and now takes the landing.** D4 settled
    /// the slice-5 half of the question: Health is its own section, Home is not
    /// folded into it, and Health did not take the landing spot. The landing
    /// itself was `.browse` from M1 until the design port, when the maintainer
    /// moved it to `.home` (2026-08-07) — the design document opens on Home,
    /// and by then Home carried the attention cards and snapshot that make a
    /// landing worth having. The history is recorded here rather than removed,
    /// because a deleted question is indistinguishable from one that was never
    /// asked.
    case discover
    case browse
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
        case .discover: "Discover"
        case .browse: "Search"
        case .caskBrowse: "Browse"
        case .caskFeatured: "Featured"
        case .caskTopCharts: "Top Charts"
        case .caskRecentlyAdded: "Recently Added"
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
        default: title
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .discover: "sparkles"
        case .browse: "magnifyingglass"
        case .caskBrowse: "square.grid.2x2"
        case .caskFeatured: "star"
        case .caskTopCharts: "chart.line.uptrend.xyaxis"
        // `clock.badge.plus` does not exist in this SDK's SF Symbols; the
        // calendar variant is the verified nearest match.
        case .caskRecentlyAdded: "calendar.badge.plus"
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
        ("Overview", [.home, .discover, .browse]),
        ("Discover Casks", [.caskBrowse, .caskFeatured, .caskTopCharts, .caskRecentlyAdded]),
        ("Packages", [.installed, .favorites, .updates, .services]),
        ("Insights", [.health, .security, .cleanup]),
        ("Manage", [.taps, .brewfile, .history]),
    ]

    static let sidebarFooter: [AppSection] = [.settings]
}
