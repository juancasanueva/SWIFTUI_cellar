//
//  MenuBarSettingsGroup.swift
//  cellar
//

import SwiftUI

/// The Settings **Menu bar** card.
///
/// Exactly one row, with behaviour behind it: the switch that inserts and
/// removes the status item. Cellar still has no background schedules and no
/// notifications, so this card gains no row for either — `SettingsView`'s own
/// rule is that a control for a capability that does not exist is absent rather
/// than present-but-inert.
///
/// The card shape is reproduced here rather than borrowed, exactly as
/// `UpdatesSettingsGroup` reproduces it: `SettingsView`'s `group(_:rows:)` and
/// `row(label:sub:accessory:)` are private to it, and the point of a separate
/// file is that deleting this one file removes the whole surface.
struct MenuBarSettingsGroup: View {
    /// The copy, written once and read twice — by the row and by the switch's
    /// own accessibility title — so one surface cannot drift from the other.
    private static let rowLabel = "Show in menu bar"

    /// Optional so a preview and a test host both render with it simply absent,
    /// the way the updater seam does. Absent means the card does not appear —
    /// never an inert card with a dead switch in it.
    @Environment(MenuBarPreference.self) private var preference: MenuBarPreference?

    var body: some View {
        if let preference {
            VStack(alignment: .leading, spacing: 9) {
                Text("Menu bar")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.66)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.34))
                VStack(spacing: 0) {
                    toggleRow(preference)
                }
                .themeCard(fill: Color.white.opacity(0.02))
            }
        }
    }

    /// The switch, over a hand-built binding.
    ///
    /// Written out rather than `@Bindable` because the seam is optional here,
    /// and the same explicit `Binding(get:set:)` the updates card uses. The
    /// subtitle states the cost plainly: the status item reads what the window
    /// already holds and fetches nothing of its own.
    private func toggleRow(_ preference: MenuBarPreference) -> some View {
        row(
            label: Self.rowLabel,
            sub: "Shows how many packages are outdated beside the clock. Off unless you turn it on."
        ) {
            Toggle(
                Self.rowLabel,
                isOn: Binding(
                    get: { preference.isShown },
                    set: { preference.isShown = $0 }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityIdentifier("menu-bar-settings-toggle")
        }
    }

    // MARK: - Pieces

    private func row(
        label: String,
        sub: String,
        @ViewBuilder accessory: () -> some View
    ) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(sub)
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            Spacer(minLength: 0)
            accessory()
        }
        .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
    }
}
