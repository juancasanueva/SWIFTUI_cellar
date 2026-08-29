//
//  NpmSettingsGroup.swift
//  cellar
//

import BrewProcess
import SwiftUI

/// The npm card in Settings: the switch, the optional path, and what was found.
///
/// Its own file and its own card, so the whole opt-in surface rolls back by
/// deleting one file and one line — the discipline `UpdatesSettingsGroup` and
/// `MenuBarSettingsGroup` already follow.
///
/// It decides nothing. `NpmSettingsDisclosure` derives every string from
/// detection state, and the two `@AppStorage` values are pushed straight into
/// `NpmDetectionStore`, which owns the probing rule. What is left here is
/// layout.
struct NpmSettingsGroup: View {
    let detection: NpmDetectionStore

    @AppStorage(NpmSourcePreference.enabledKey) private var isEnabled = false
    @AppStorage(NpmSourcePreference.pathKey) private var configuredPath = ""

    private var disclosure: NpmSettingsDisclosure {
        NpmSettingsDisclosure(
            state: detection.state,
            configuredPath: NpmSourcePreference().configuredPath
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("npm")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.66)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.34))
            VStack(spacing: 0) {
                row(
                    label: "npm packages",
                    sub: "List and update globally installed npm packages · off by default"
                ) {
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("npm packages")
                        .accessibilityIdentifier("npm-source-toggle")
                }

                if isEnabled {
                    separator
                    row(label: "npm binary", sub: "Leave empty to detect one automatically") {
                        TextField("Detect automatically", text: $configuredPath)
                            .textFieldStyle(.plain)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 280)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Theme.controlFillLoud,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .accessibilityIdentifier("npm-path-field")
                    }

                    detected
                }
            }
            .themeCard(fill: Color.white.opacity(0.02))
        }
        // The store is the only thing that probes, so the preference is pushed
        // into it rather than read out of it. `task` covers launch; the two
        // `onChange`s cover a change made while Settings is open, which is the
        // "without a relaunch" requirement.
        .task {
            detection.isEnabled = isEnabled
            detection.configuredPath = NpmSourcePreference().configuredPath
        }
        .onChange(of: isEnabled) { _, enabled in
            detection.isEnabled = enabled
        }
        .onChange(of: configuredPath) { _, _ in
            detection.configuredPath = NpmSourcePreference().configuredPath
        }
    }

    @ViewBuilder
    private var detected: some View {
        let disclosure = disclosure

        if let note = disclosure.note {
            separator
            row(label: "npm", sub: note) { EmptyView() }
                .accessibilityIdentifier("npm-detection-note")
        } else {
            if let path = disclosure.path {
                separator
                row(label: "Detected npm", sub: disclosure.origin ?? "") { monospaced(path) }
                    .accessibilityIdentifier("npm-detected-path")
            }
            if let version = disclosure.version {
                separator
                row(label: "npm version", sub: "As reported by the detected binary") {
                    monospaced(version)
                }
            }
            if let prefix = disclosure.prefix {
                separator
                row(label: "Global prefix", sub: "Where -g packages are installed") {
                    monospaced(prefix)
                }
            }
        }
    }

    // MARK: - Layout
    //
    // The card shape is reproduced here rather than borrowed, exactly as
    // `UpdatesSettingsGroup` reproduces it: `SettingsView`'s `group` and `row`
    // are private to it, and the point of a separate file is that deleting this
    // one file removes the whole surface.

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

    private func monospaced(_ text: String) -> some View {
        Text(text)
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
