//
//  MenuBarPopoverView.swift
//  cellar
//

import BrewClient
import SwiftUI

/// The whole menu-bar surface: what is outdated, one bulk upgrade, the services
/// Cellar knows about, and a way back to the window.
///
/// **A projection reader, and nothing else.** It loads nothing, fetches nothing,
/// spawns nothing and refreshes nothing: every number and every row on it comes
/// from the value it is handed. The single asynchronous hop this surface is
/// allowed — one services refresh when it appears — lives one file up, on the
/// scene, which is what makes the prohibition here absolute rather than "except
/// for the one we needed".
///
/// It also raises no confirmation. The shared pending-confirmation channel's
/// only presenter is the main window, so a request raised from here with no
/// window open would latch unanswered and block every later confirmation in the
/// app. Every verb offered below needs none, which is asserted rather than
/// assumed.
///
/// No package artwork either: that pipeline reaches the network, so a cask icon
/// in a popover would turn opening a menu into an outbound request. An entry
/// presents its name and its two versions, none of which has to be fetched.
struct MenuBarPopoverView: View {
    let projection: MenuBarProjection
    let operations: OperationCenter
    /// A plain closure, so this surface cannot inspect what it opened — or make
    /// anything else conditional on a window existing.
    let openMainWindow: () -> Void

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            countRow
            HairlineDivider()
            outdatedSection
            HairlineDivider()
            upgradeRow
            if projection.services.isEmpty == false {
                HairlineDivider()
                servicesSection
            }
            HairlineDivider()
            openRow
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        .frame(width: 320)
        .background(Theme.windowBackground)
    }

    // MARK: - The count

    /// The number, taken from the same value the status item's title comes from.
    ///
    /// Reading the projection's title rather than formatting the count here is
    /// what makes the popover and the status item literally unable to disagree,
    /// and it carries the zero case for free: the title is absent when nothing
    /// is outdated, so there is no `0` for this surface to decide how to draw.
    /// The reassuring sentence is the projection's, not this view's. A popover
    /// that owned the literal could still print it over an npm nobody managed to
    /// check; reading `upToDateCopy` means the sentence is simply absent
    /// whenever it may not be said (`menu-bar`: offline npm is stated, not
    /// hidden).
    private var countRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                if let title = projection.statusItemTitle {
                    StatusPill(label: title, background: theme.tint(0.22), foreground: theme.light)
                    Text("outdated")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                } else if let upToDate = projection.upToDateCopy {
                    Text(upToDate)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer(minLength: 0)
            }
            // Absent when npm answered, and absent entirely when the source is
            // off — so a brew-only Mac sees the shipped row byte for byte.
            if let notChecked = projection.npmNotCheckedCopy {
                Text(notChecked)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .accessibilityIdentifier("menu-bar-npm-not-checked")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - What is outdated

    @ViewBuilder
    private var outdatedSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Updates")
            ForEach(projection.topOutdated) { entry in
                entryRow(entry)
            }
            if let more = projection.andMoreLabel {
                Text(more)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            if projection.topOutdated.isEmpty {
                Text("Nothing is waiting for an update.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    /// One outdated package. Grouped into a single accessibility element, so a
    /// screen reader announces "wget, 1.21.4 to 1.25.0" rather than three
    /// unrelated fragments.
    private func entryRow(_ entry: MenuBarProjection.OutdatedEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.name)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(entry.installedVersion) → \(entry.catalogVersion)")
                .font(Theme.mono(10.5))
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(entry.installedVersion) to \(entry.catalogVersion)")
    }

    // MARK: - The one bulk verb

    /// **Uncounted, on purpose.** The badge carries the number and the button
    /// carries none, so the label cannot announce a number different from the
    /// set `brew upgrade` acts on — the bulk-label rule satisfied by
    /// construction rather than by argument.
    ///
    /// The disclosed command is the shipped command's own, so the popover and
    /// the installed list cannot word one submission two ways.
    private var upgradeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button("Upgrade all") { operations.submit(.upgradeAll) }
                    .buttonStyle(ActionPillStyle())
                    .accessibilityIdentifier("menu-bar-upgrade-all")
                    .accessibilityLabel("Upgrade all outdated packages")
                Text(MutationCommand.upgradeAll.displayCommand)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
                Spacer(minLength: 0)
                CopyCommandButton(text: MutationCommand.upgradeAll.displayCommand)
                    .accessibilityIdentifier("menu-bar-copy-command")
            }
            // The verb is unchanged and stays unchanged: it submits bare
            // `brew upgrade` and fans out to nothing. What it does *not* cover
            // is said here rather than by widening it (`menu-bar` MB4).
            if let disclosure = projection.npmUpgradeDisclosure {
                Text(disclosure)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .accessibilityIdentifier("menu-bar-npm-disclosure")
            }
        }
        .disabled(!operations.isAvailable)
        .help(operations.unavailableGuidance ?? "Upgrade every outdated package")
    }

    // MARK: - Services

    /// Last known, never fetched here, and absent rather than empty when Cellar
    /// has nothing to report — an empty list standing for a failure would be a
    /// confident claim this surface cannot make.
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Services")
            ForEach(projection.services) { service in
                serviceRow(service)
            }
        }
    }

    /// The controls are the shipped ones, narrowed by the rule that lives in
    /// `BrewClient`. This surface composes no verb, no argv and no
    /// applicability rule of its own, and it never collapses start-at-login and
    /// run-once into a single switch.
    private func serviceRow(_ service: ServiceRecord) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(service.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(service.status.label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            Spacer(minLength: 8)
            ServiceControls(
                service: service,
                operations: operations,
                controls: ServiceRowControl.compactControls(for: service.status),
                identifierPrefix: "menu-bar-service"
            )
        }
    }

    // MARK: - Back to the window

    private var openRow: some View {
        HStack(spacing: 8) {
            Button(action: openMainWindow) {
                Label("Open Cellar", systemImage: "macwindow")
            }
            .buttonStyle(ShellChipButtonStyle())
            .accessibilityIdentifier("menu-bar-open-cellar")
            .accessibilityLabel("Open the Cellar window")
            Spacer(minLength: 0)
        }
    }
}
