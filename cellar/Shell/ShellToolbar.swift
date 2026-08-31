//
//  ShellToolbar.swift
//  cellar
//

import SwiftUI

/// The shell's toolbar row, expressed as native toolbar content: section label
/// on the left beside the sidebar toggle, Refresh and Activity on the right.
///
/// Toolbar items rather than a drawn strip because macOS clips app content out
/// of the titlebar region — a custom view laid under it stays clickable but
/// never paints. The native row is also what keeps the sidebar toggle, the
/// traffic lights and these controls on one shared baseline.
struct ShellToolbarItems: ToolbarContent {
    let section: AppSection
    /// Whether the row draws the title and controls at all. The cask pages
    /// render `false`: their pinned capsule bar carries the page name and the
    /// same `ShellHeaderControls`, so the toolbar row would say it all twice.
    var showsPageChrome: Bool = true
    /// The same launch-and-activation refresh the app already runs; the button
    /// adds a way to ask for it, not a second pipeline.
    let refresh: @MainActor () async -> Void
    @Binding var isActivityExpanded: Bool

    var body: some ToolbarContent {
        if showsPageChrome {
            ToolbarItem(placement: .navigation) {
                Text(section.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            // Pushes the actions to the trailing edge; without it every item
            // packs in beside the title. A plain Spacer in a ToolbarItem
            // rather than ToolbarSpacer, which needs macOS 26.
            ToolbarItem {
                Spacer()
            }
            ToolbarItem(placement: .primaryAction) {
                ShellHeaderControls(refresh: refresh, isActivityExpanded: $isActivityExpanded)
            }
        }
    }
}

/// The discover pages' capsule header without their collection controls:
/// title, an optional count, and the shared Refresh/Activity pair. Home and
/// Search catalog pin it at the shell level, so every page leads with the
/// same card whether or not it browses a collection.
struct ShellTitleBar: View {
    let title: String
    var countLabel: String? = nil
    var shellControls: ShellHeaderControls?
    /// A section-owned control drawn before the shared pair — the History
    /// bar's search field.
    var leadingAccessories: AnyView? = nil
    /// Section-owned controls drawn after the shared pair — the History bar
    /// carries its clear chip here.
    var accessories: AnyView? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let countLabel {
                Text(countLabel)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if let leadingAccessories {
                leadingAccessories
            }
            if let shellControls {
                shellControls
            }
            if let accessories {
                accessories
            }
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
        .themeCard(radius: 999)
    }
}

/// The shell chip as a button style, so a section's own toolbar buttons (the
/// Taps Brewfile pair) sit beside `ShellHeaderControls` in the same dress
/// without duplicating its metrics.
struct ShellChipButtonStyle: ButtonStyle {
    var iconOnly: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(ShellChipLabelStyle(iconOnly: iconOnly))
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .fixedSize()
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

private struct ShellChipLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
            if !iconOnly {
                configuration.title
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
    }
}

/// The Refresh and Activity pair as one reusable view: the toolbar row renders
/// it on most sections, and the cask pages draw the same pair inside their
/// pinned capsule bar instead — one control, two homes, no second pipeline.
struct ShellHeaderControls: View {
    let refresh: @MainActor () async -> Void
    @Binding var isActivityExpanded: Bool

    @State private var isRefreshing = false

    var body: some View {
        // The pair's degradation order in a tight bar: full labels, then
        // icon-only — a whole label or none, never "Ref…".
        ViewThatFits(in: .horizontal) {
            controls(iconOnly: false)
            controls(iconOnly: true)
        }
    }

    private func controls(iconOnly: Bool) -> some View {
        HStack(spacing: 8) {
            button(
                label: iconOnly ? nil : "Refresh",
                systemImage: "arrow.clockwise",
                identifier: "shell-refresh",
                spinning: isRefreshing
            ) {
                guard !isRefreshing else { return }
                isRefreshing = true
                Task {
                    await refresh()
                    isRefreshing = false
                }
            }
            .help("Refresh")
            button(
                label: iconOnly ? nil : "Activity",
                systemImage: "terminal",
                identifier: "shell-activity"
            ) {
                isActivityExpanded.toggle()
            }
            .help("Activity")
        }
    }

    private func button(
        label: String?,
        systemImage: String,
        identifier: String,
        spinning: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(
                        spinning
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: spinning
                    )
                if let label {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            // Never truncates: in a tight bar the flexible search field is
            // what gives, not these labels.
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
