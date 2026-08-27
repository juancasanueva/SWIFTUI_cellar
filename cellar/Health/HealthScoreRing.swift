//
//  HealthScoreRing.swift
//  cellar
//

import SwiftUI

/// The score gauge: quiet full track, accent arc by score. The Health hero's
/// ring, extracted so the Home card draws the same one — stroke and type
/// scale with the frame, proportioned to the design's original 118.
struct HealthScoreRing: View {
    let value: Int
    let headline: String
    /// One default for both surfaces, so the hero and the Home card stay the
    /// same size without either naming a number.
    var size: CGFloat = 128

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(value, 0), 100)) / 100)
                .stroke(theme.base, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(headline)
                    .font(Theme.mono(30 * scale, weight: .semibold))
                    .kerning(-0.9 * scale)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("health-score")
                Text(HealthCopy.scoreRingCaption)
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.38))
            }
        }
        .frame(width: size, height: size)
    }

    private var scale: CGFloat { size / 118 }
    private var lineWidth: CGFloat { 9 * scale }
}
