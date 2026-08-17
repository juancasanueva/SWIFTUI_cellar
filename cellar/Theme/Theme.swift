//
//  Theme.swift
//  cellar
//

import SwiftUI

extension Color {
    /// The design speaks in 6-digit hex; this keeps the port literal.
    init(designHex value: UInt32) {
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    init(_ palette: AccentPalette, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double(palette.red) / 255,
            green: Double(palette.green) / 255,
            blue: Double(palette.blue) / 255,
            opacity: opacity
        )
    }
}

/// The design document's fixed tokens: everything that is *not* derived from
/// the accent. Names follow the design's roles rather than its raw values so a
/// reader of a call site learns what the colour is for.
enum Theme {
    // MARK: - Surfaces

    /// The window itself (`#1a1b1e`).
    static let windowBackground = Color(designHex: 0x1A1B1E)
    /// The log drawer and code wells (`#0f1012` / `#101113`).
    static let well = Color(designHex: 0x101113)
    static let logWell = Color(designHex: 0x0F1012)
    /// Sidebar wash (`rgba(255,255,255,.028)`).
    static let sidebarWash = Color.white.opacity(0.028)
    /// Card and row fills, from quietest to loudest.
    static let rowFill = Color.white.opacity(0.018)
    static let cardFill = Color.white.opacity(0.022)
    static let cardFillLoud = Color.white.opacity(0.025)
    /// Control fills (buttons, fields).
    static let controlFill = Color.white.opacity(0.07)
    static let controlFillLoud = Color.white.opacity(0.08)

    // MARK: - Lines

    static let border = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.07)
    static let separator = Color.white.opacity(0.06)

    // MARK: - Text

    /// `#f4f2ef` — every heading and primary label.
    static let textPrimary = Color(designHex: 0xF4F2EF)
    static let textSecondary = Color.white.opacity(0.5)
    static let textTertiary = Color.white.opacity(0.42)
    static let textQuaternary = Color.white.opacity(0.34)
    static let textFaint = Color.white.opacity(0.3)
    /// Body copy that must stay readable (`rgba(255,255,255,.72)`).
    static let textBody = Color.white.opacity(0.72)
    /// Mono values in facts and wells (`#dfe2e6` / `#cfd3d8`).
    static let textMono = Color(designHex: 0xDFE2E6)

    // MARK: - Status

    /// Danger pair: base for dots/strokes, `fg` for text on tinted ground.
    static let dangerBase = Color(designHex: 0xE85A50)
    static let dangerText = Color(designHex: 0xF08A80)
    static func dangerTint(_ opacity: Double) -> Color {
        Color(.sRGB, red: 232 / 255, green: 90 / 255, blue: 80 / 255, opacity: opacity)
    }

    /// Success pair.
    static let successBase = Color(designHex: 0x4AC26B)
    static let successText = Color(designHex: 0x7AC48C)
    static func successTint(_ opacity: Double) -> Color {
        Color(.sRGB, red: 122 / 255, green: 196 / 255, blue: 140 / 255, opacity: opacity)
    }

    /// Informational blue and the cask violet.
    static let infoText = Color(designHex: 0x7FB2E8)
    static func infoTint(_ opacity: Double) -> Color {
        Color(.sRGB, red: 127 / 255, green: 178 / 255, blue: 232 / 255, opacity: opacity)
    }
    static let caskText = Color(designHex: 0xC197E0)
    static func caskTint(_ opacity: Double) -> Color {
        Color(.sRGB, red: 190 / 255, green: 140 / 255, blue: 220 / 255, opacity: opacity)
    }

    // MARK: - Package tiles

    /// The five `(background, foreground)` pairs behind initial tiles.
    static let tilePairs: [(background: Color, foreground: Color)] = [
        (Color(.sRGB, red: 224 / 255, green: 164 / 255, blue: 92 / 255, opacity: 0.18), Color(designHex: 0xE0A45C)),
        (Color(.sRGB, red: 108 / 255, green: 164 / 255, blue: 222 / 255, opacity: 0.18), Color(designHex: 0x7FB2E8)),
        (Color(.sRGB, red: 122 / 255, green: 196 / 255, blue: 140 / 255, opacity: 0.18), Color(designHex: 0x7AC48C)),
        (Color(.sRGB, red: 190 / 255, green: 140 / 255, blue: 220 / 255, opacity: 0.18), Color(designHex: 0xC197E0)),
        (Color(.sRGB, red: 226 / 255, green: 132 / 255, blue: 120 / 255, opacity: 0.18), Color(designHex: 0xE89086)),
    ]

    static func tile(for name: String) -> (background: Color, foreground: Color) {
        tilePairs[PackageTilePalette.index(for: name)]
    }

    // MARK: - Type

    /// The design uses IBM Plex Mono for versions, counts, paths and commands;
    /// the system monospaced face is its native stand-in.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Building blocks

/// A design card: quiet fill, half-point border, continuous corners.
private struct ThemeCard: ViewModifier {
    var fill: Color
    var stroke: Color
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.5)
            )
    }
}

extension View {
    func themeCard(
        fill: Color = Theme.cardFill,
        stroke: Color = Theme.border,
        radius: CGFloat = 11
    ) -> some View {
        modifier(ThemeCard(fill: fill, stroke: stroke, radius: radius))
    }
}

/// The design's filled accent button — dark text on the accent, matching the
/// Brewfile section's primary — for a dialog's one default action. The system
/// prominent style paints white on the accent, which the design never does.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Theme.windowBackground)
            .padding(.horizontal, 13)
            .frame(height: 29)
            .background(theme.base, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}

/// The design's 38×22 pill switch. `Toggle` restyled rather than rebuilt so
/// bindings, accessibility and keyboard behaviour stay native.
struct ThemeToggleStyle: ToggleStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                if configuration.isOn { Spacer(minLength: 0) }
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                if !configuration.isOn { Spacer(minLength: 0) }
            }
            .padding(2)
            .frame(width: 38, height: 22)
            .background(
                configuration.isOn ? accent : Color.white.opacity(0.14),
                in: Capsule()
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}
