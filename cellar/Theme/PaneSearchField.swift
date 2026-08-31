//
//  PaneSearchField.swift
//  cellar
//

import SwiftUI

/// The design's in-pane search field: a quiet 27-point pill with a glass icon,
/// used by every list pane instead of the window-toolbar search slot.
struct PaneSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.35))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityIdentifier("pane-search-field")
    }
}

/// The design's action button, in the detail page Actions section's dress:
/// the quiet tone's solid neutral fill (or the danger tone's tinted fill and
/// hairline) on a 7-point rounded rectangle, 29 points tall.
///
/// Deliberately **not** an accent-tinted pill: the earlier accent-tint version
/// sat above lists whose `FilterChip` row wears the same tint at the same text
/// size, and users read the commands as a second row of filters. Sharing the
/// detail buttons' height, weight and neutral fill is what makes a command
/// read as pressable — and as a different species from the capsule chips.
struct ActionPillStyle: ButtonStyle {
    var isDestructive = false
    @Environment(\.isEnabled) private var isEnabled

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(isDestructive ? Theme.dangerText : Theme.textPrimary)
            .padding(.horizontal, 13)
            .frame(height: 29)
            .background(
                isDestructive ? Theme.dangerTint(0.12) : Theme.controlFillLoud,
                in: shape
            )
            .overlay {
                if isDestructive {
                    shape.strokeBorder(Theme.dangerTint(0.28), lineWidth: 0.5)
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.4))
    }
}

/// The design's filter chip: a 14-point-radius pill that fills with accent
/// tint when active.
struct FilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isOn ? theme.light : Color.white.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    isOn ? theme.tint(0.18) : Color.white.opacity(0.04),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? theme.tint(0.3) : Color.white.opacity(0.07),
                        lineWidth: 0.5
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
