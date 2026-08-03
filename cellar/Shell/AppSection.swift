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
    case browse
    case installed
    /// The background services Homebrew manages.
    ///
    /// Its own place rather than a lens on Installed: a service is its own
    /// entity, not a field of a package, and one whose name matches an
    /// installed formula is still not that formula (service-management SM12).
    case services
    /// The durable record of every mutation Cellar performed.
    ///
    /// Favorites is deliberately **not** here: it is a filter chip on the
    /// Installed list, because a favorite is a lens on what you have rather
    /// than a separate place (settled Q4).
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .browse: "Browse"
        case .installed: "Installed"
        case .services: "Services"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .browse: "square.grid.2x2"
        case .installed: "shippingbox"
        case .services: "bolt.horizontal.circle"
        case .history: "clock.arrow.circlepath"
        }
    }
}
