//
//  ThemeStore.swift
//  cellar
//

import SwiftUI

/// The one accent choice, observable app-wide and persisted across launches.
///
/// Selection tints, badges, primary buttons and charts all derive from this
/// single value, exactly as the design document derives them from its `accent`
/// prop. Persistence is a plain default: the choice is a preference, not data.
@MainActor
@Observable
final class ThemeStore {
    private static let key = "accentHex"

    private let defaults: UserDefaults

    var accent: AccentPalette {
        didSet {
            defaults.set(accent.hexString, forKey: Self.key)
            syncSystemAccent()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.key)
        accent = stored.flatMap(AccentPalette.init(hex:)) ?? .default
        syncSystemAccent()
    }

    /// Points the app's *system* accent at the nearest built-in colour.
    ///
    /// AppKit paints native list selection (the Installed multi-select, Taps,
    /// Services) with the system accent, over any row background and beyond
    /// any SwiftUI tint. macOS honours a per-app `AppleAccentColor` default,
    /// but only from the fixed system set — so the chosen accent maps to its
    /// nearest neighbour, and the value is read at launch: a change applies
    /// fully after the app is reopened.
    private func syncSystemAccent() {
        // The system set: 0 red, 1 orange, 2 yellow, 3 green, 4 blue,
        // 5 purple, 6 pink.
        let nearest: [String: Int] = [
            "#e0a45c": 1, "#d9c15c": 2, "#7fb85c": 3, "#4fae7b": 3,
            "#4fada8": 4, "#5b8def": 4, "#7b7ae0": 5, "#b47ae0": 5,
            "#d97ab0": 6, "#c98a6a": 1,
        ]
        guard let value = nearest[accent.hexString] else { return }
        defaults.set(value, forKey: "AppleAccentColor")
    }

    // MARK: - Derived colours, in the design's vocabulary

    /// `A` — the accent itself.
    var base: Color { Color(accent) }
    /// `AL` — text on accent-tinted surfaces.
    var light: Color { Color(accent.light) }
    /// The gradient end used by the app-icon block.
    var dark: Color { Color(accent.dark) }
    /// `acc.tNN` — the alpha ladder behind tinted fills and borders.
    func tint(_ opacity: Double) -> Color { Color(accent, opacity: opacity) }
}
