//
//  ShellToolbar.swift
//  cellar
//

import SwiftUI

/// The design's 52-point header strip: section label on the left, Refresh and
/// Activity on the right, on a whisper of a wash above a hairline.
struct ShellToolbar: View {
    let section: AppSection
    /// The same launch-and-activation refresh the app already runs; the button
    /// adds a way to ask for it, not a second pipeline.
    let refresh: @MainActor () async -> Void
    @Binding var isActivityExpanded: Bool

    @State private var isRefreshing = false

    var body: some View {
        HStack(spacing: 14) {
            Text(section.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            HStack(spacing: 7) {
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
                button(
                    label: "Activity",
                    systemImage: "terminal",
                    identifier: "shell-activity"
                ) {
                    isActivityExpanded.toggle()
                }
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
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
