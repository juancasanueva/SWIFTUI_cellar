//
//  SettingsView.swift
//  cellar
//

import BrewProcess
import SwiftUI

/// The app's own preferences, in the design's grouped-card arrangement.
///
/// Only rows with something real behind them are rendered: the brew binary is
/// the detection store's answer, and the accent swatches write the one
/// `ThemeStore` every tinted surface reads. Rows the design sketches for
/// capabilities Cellar does not have (background checks that run on their own,
/// and the alerts that would announce them) are deliberately absent rather than
/// present-but-inert.
struct SettingsView: View {
    let brewDetection: BrewDetectionStore
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 27, weight: .semibold))
                    .kerning(-0.6)
                    .foregroundStyle(Theme.textPrimary)

                group("Homebrew") {
                    row(
                        label: "brew binary",
                        sub: "Detected automatically on launch"
                    ) {
                        Text(brewPath)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Theme.controlFillLoud,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    if let version = brewVersion {
                        separator
                        row(
                            label: "Homebrew version",
                            sub: "As reported by the detected installation"
                        ) {
                            Text(version)
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(
                                    Theme.controlFillLoud,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                        }
                    }
                }

                group("Interface") {
                    row(
                        label: "Accent colour",
                        sub: "Used for selection, badges, primary buttons and charts"
                    ) {
                        HStack(spacing: 7) {
                            ForEach(AccentPalette.choices, id: \.name) { choice in
                                swatch(choice.name, palette: choice.palette)
                            }
                        }
                    }
                }

                // Its own file and its own card, so the whole update surface
                // rolls back by deleting one file and this one line.
                UpdatesSettingsGroup()

                MenuBarSettingsGroup()

                freeCard
            }
            .frame(maxWidth: 760, alignment: .topLeading)
            .padding(EdgeInsets(top: 28, leading: 34, bottom: 44, trailing: 34))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.windowBackground)
        .accessibilityIdentifier("settings-section")
    }

    private var brewPath: String {
        brewDetection.state.installation?.executableURL.path ?? "Not detected yet"
    }

    private var brewVersion: String? {
        brewDetection.state.installation.map {
            "brew \($0.version.major).\($0.version.minor).\($0.version.patch)"
        }
    }

    // MARK: - Pieces

    private func group(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.66)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.34))
            VStack(spacing: 0) { rows() }
                .themeCard(fill: Color.white.opacity(0.02))
        }
    }

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

    private func swatch(_ name: String, palette: AccentPalette) -> some View {
        let isCurrent = palette == theme.accent
        return Button {
            theme.accent = palette
        } label: {
            Circle()
                .fill(Color(palette))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(Theme.windowBackground, lineWidth: 2)
                        .padding(-1)
                )
                .overlay(
                    Circle()
                        .stroke(isCurrent ? Color(palette) : .clear, lineWidth: 1.5)
                        .padding(-2.75)
                )
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityIdentifier("accent-\(name.lowercased())")
    }

    /// The design's closing card, wording kept verbatim.
    private var freeCard: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Cellar is free, and stays free")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("No accounts, no telemetry, no paid tier.")
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
        .themeCard(fill: theme.tint(0.07), stroke: theme.tint(0.24))
    }
}
