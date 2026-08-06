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
    /// Advisory coverage, CVE findings, and artifact integrity.
    ///
    /// Between Cleanup and History because it is read-only visibility over what
    /// is installed, like Cleanup, rather than a record of what Cellar did.
    case security
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
        case .taps: "Taps"
        case .services: "Services"
        case .cleanup: "Cleanup"
        case .security: "Security"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .browse: "square.grid.2x2"
        case .installed: "shippingbox"
        case .taps: "externaldrive.connected.to.line.below"
        case .services: "bolt.horizontal.circle"
        case .cleanup: "externaldrive.badge.timemachine"
        case .security: "checkmark.shield"
        case .history: "clock.arrow.circlepath"
        }
    }
}
