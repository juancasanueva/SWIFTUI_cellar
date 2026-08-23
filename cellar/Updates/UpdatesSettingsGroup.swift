//
//  UpdatesSettingsGroup.swift
//  cellar
//

import SwiftUI
import Updates

/// The Settings **Updates** card.
///
/// Exactly two rows, both with behaviour behind them: the automatic-checking
/// toggle and the last-checked label. The design also sketched an update-channel
/// picker; Cellar has no channels — a prerelease never enters the feed at all —
/// so the picker would be a control that changes nothing, and `SettingsView`'s
/// own rule is that such rows are absent rather than present-but-inert.
///
/// The card shape is reproduced here rather than borrowed: `SettingsView`'s
/// `group(_:rows:)` and `row(label:sub:accessory:)` are private to it, and the
/// point of a separate file is that deleting this one file removes the whole
/// surface.
struct UpdatesSettingsGroup: View {
    /// Optional so a preview and a test host both render with it simply absent,
    /// the way the release-notes credential seam does. Absent means the card
    /// does not appear — never an inert card with dead controls in it.
    @Environment(\.appUpdater) private var updater

    var body: some View {
        if let updater {
            VStack(alignment: .leading, spacing: 9) {
                Text("Updates")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.66)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.34))
                VStack(spacing: 0) {
                    automaticRow(updater)
                    separator
                    lastCheckedRow(updater)
                }
                .themeCard(fill: Color.white.opacity(0.02))
            }
        }
    }

    // MARK: - Rows

    /// The toggle, over a hand-built binding.
    ///
    /// `@Bindable` needs a concrete `@Observable` type and the seam is
    /// deliberately an existential, so the four lines are written out. The
    /// subtitle names the egress plainly: a check is a network request, and
    /// Cellar says so wherever it asks to make one.
    private func automaticRow(_ updater: any AppUpdating) -> some View {
        row(
            label: "Check for updates automatically",
            sub: "Contacts Cellar's update feed in the background. Off unless you turn it on."
        ) {
            Toggle(
                "Check for updates automatically",
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityIdentifier("updates-automatic-toggle")
        }
    }

    /// The last-checked wording, from the value type that owns it.
    private func lastCheckedRow(_ updater: any AppUpdating) -> some View {
        row(
            label: "Last check",
            sub: "Cellar reports the check it actually made, and says so when it never has."
        ) {
            Text(UpdateCheckPresentation(lastCheck: updater.lastUpdateCheckDate, now: Date()).label)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.55))
                .accessibilityIdentifier("updates-last-checked")
        }
    }

    // MARK: - Pieces

    private var separator: some View {
        Rectangle().fill(Theme.separator).frame(height: 0.5)
    }

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

// MARK: - The updater seam in the environment

extension EnvironmentValues {
    /// The updater, held by the app and read by the Settings card.
    ///
    /// An environment value rather than a parameter threaded through the section
    /// switch, and optional so a preview and a test host both render with it
    /// absent. It is `any AppUpdating` and never the concrete checker, so a
    /// UI-test launch injects an in-memory updater and the real one is never
    /// constructed.
    @Entry var appUpdater: (any AppUpdating)?
}
