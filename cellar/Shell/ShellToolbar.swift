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
    /// A title shown in place of `section.title` when the section alone cannot
    /// name the page — the category pages, where the case says "Category" and
    /// the shell knows which one. `nil` keeps the section's own title.
    var titleOverride: String? = nil
    /// The same launch-and-activation refresh the app already runs; the button
    /// adds a way to ask for it, not a second pipeline.
    let refresh: @MainActor () async -> Void
    @Binding var isActivityExpanded: Bool

    @State private var isRefreshing = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(titleOverride ?? section.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        // Pushes the actions to the trailing edge; without it every item packs
        // in beside the title.
        ToolbarSpacer(.flexible)
        ToolbarItem(placement: .primaryAction) {
            button(
                label: "Refresh",
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
        }
        ToolbarItem(placement: .primaryAction) {
            button(
                label: "Activity",
                systemImage: "terminal",
                identifier: "shell-activity"
            ) {
                isActivityExpanded.toggle()
            }
        }
    }

    private func button(
        label: String,
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
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
