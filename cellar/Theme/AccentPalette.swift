//
//  AccentPalette.swift
//  cellar
//

import Foundation

/// One accent colour and the variants the design derives from it.
///
/// The design document (`Cellar.dc.html`) computes every accent-tinted surface
/// from a single hex value: a `light` variant mixed 30% toward white for text
/// on tinted surfaces, a `dark` variant mixed 38% toward black for gradients,
/// and a ladder of alpha tints for backgrounds and borders. This type is that
/// arithmetic, kept pure so it stays provable without a window.
nonisolated struct AccentPalette: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int

    init?(hex: String) {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = Int((value >> 16) & 0xFF)
        green = Int((value >> 8) & 0xFF)
        blue = Int(value & 0xFF)
    }

    private init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var hexString: String {
        String(format: "#%02x%02x%02x", red, green, blue)
    }

    /// Text-on-tint variant: 30% toward white, the design's `AL`.
    var light: AccentPalette { mixed(toward: 255, amount: 0.3) }

    /// Gradient-end variant: 38% toward black.
    var dark: AccentPalette { mixed(toward: 0, amount: 0.38) }

    /// Component-wise `round(x + (to - x) * amount)`, matching the design's
    /// `mix()` exactly so no surface shifts a shade when ported.
    func mixed(toward target: Int, amount: Double) -> AccentPalette {
        func mix(_ component: Int) -> Int {
            Int((Double(component) + (Double(target) - Double(component)) * amount).rounded())
        }
        return AccentPalette(red: mix(red), green: mix(green), blue: mix(blue))
    }

    // MARK: - The ten choices

    static let `default` = AccentPalette.choices[0].palette

    /// The design's accent swatches, in its order, amber first.
    static let choices: [(name: String, palette: AccentPalette)] = [
        ("Amber", "#e0a45c"), ("Gold", "#d9c15c"), ("Moss", "#7fb85c"),
        ("Green", "#4fae7b"), ("Teal", "#4fada8"), ("Blue", "#5b8def"),
        ("Indigo", "#7b7ae0"), ("Violet", "#b47ae0"), ("Magenta", "#d97ab0"),
        ("Clay", "#c98a6a"),
    ].compactMap { name, hex in
        AccentPalette(hex: hex).map { (name, $0) }
    }
}

/// The five-colour palette behind package initial tiles.
///
/// The design hashes the package name's character codes so a package keeps its
/// tile colour across launches, lists and machines — identity, not decoration.
nonisolated enum PackageTilePalette {
    static let pairCount = 5

    static func index(for name: String) -> Int {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % pairCount
    }
}
