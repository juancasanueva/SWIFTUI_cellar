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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .browse: "Browse"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .browse: "square.grid.2x2"
        }
    }
}
