//
//  MutationMenu.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SwiftUI

/// Every mutation affordance for one package, in one place.
///
/// The view owns no rule at all: whether a command needs confirming, what its
/// exact argv is and what the copy button copies are all computed properties on
/// `MutationCommand`, proven in the package's own suite (design D10). When the
/// centre reports no runner the affordances are **unavailable** — disabled with
/// the guidance attached — rather than failing at spawn time
/// (package-mutation PM7).
struct MutationMenu: View {
    let center: OperationCenter
    let entry: PackageEntry
    /// The metadata store, when the hosting surface has one. Snooze is a
    /// metadata write rather than a mutation, so it rides in this menu only
    /// where installed packages live (`InstalledRow`); the catalog surfaces
    /// pass nothing and the item is simply absent.
    var metadata: MetadataStore? = nil

    /// The entry's identity, proven safe to put in argv.
    ///
    /// `nil` only for a name brew could read as an option, in which case every
    /// package-naming affordance is simply absent — an unvalidated command is
    /// not representable, so there is nothing to disable (design D9, PM9).
    private var target: PackageTarget? { PackageTarget(entry.id) }

    /// Which executable's availability gates this menu: brew's for a formula
    /// or cask, npm's for a global package (design D13).
    private var source: PackageSource { entry.id.kind.source }

    var body: some View {
        Menu {
            switch source {
            case .homebrew:
                if let target {
                    if entry.isInstalled {
                        if let appURL = CaskAppLauncher.installedAppURL(for: entry) {
                            Button("Open") { CaskAppLauncher.open(appURL) }
                            Divider()
                        }
                        installedActions(target)
                    } else {
                        action("Install", .install(target))
                    }
                    Divider()
                    Button("Copy install command") {
                        copy(MutationCommand.install(target).displayCommand)
                    }
                }
            case .npm:
                npmActions
            }
        } label: {
            Label("Package actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!center.isAvailable(for: source))
        .help(center.unavailableGuidance(for: source) ?? "Install, upgrade or remove \(entry.displayName)")
    }

    /// npm's verbs, read from the one projection the detail pane also reads
    /// (`NpmCommand.available(for:)`), so the two surfaces cannot drift.
    /// Uninstall sits below a divider for the reason brew's does: destructive,
    /// and therefore confirmed, apart from the reversible verb above it.
    @ViewBuilder
    private var npmActions: some View {
        let commands = NpmCommand.available(for: entry)
        ForEach(commands, id: \.displayCommand) { command in
            if case .uninstall = command, commands.count > 1 {
                Divider()
            }
            Button(command.title) { submit(command) }
        }
        snoozeItem
    }

    /// The same eligibility and toggle as the detail pane's snooze button:
    /// outdated, with an offered version to name, through the shipped store
    /// API only (LPM5). Exact string equality decides snoozed-ness — no
    /// comparator, same as everywhere else in the capability.
    @ViewBuilder
    private var snoozeItem: some View {
        if let metadata, metadata.availability.isAvailable,
           let installed = entry.installed, installed.isOutdated {
            let offered = installed.catalogVersion
            if offered.isEmpty == false {
                let isSnoozed = PackageMetadata.isSnoozed(
                    offering: offered,
                    snoozedVersion: metadata.snapshot[entry.id]?.snoozedVersion
                )
                Button(isSnoozed ? "Unsnooze" : "Snooze \(offered)") {
                    if isSnoozed {
                        metadata.unsnooze(entry.id)
                    } else {
                        metadata.snooze(entry.id, offering: offered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func installedActions(_ target: PackageTarget) -> some View {
        if entry.installed?.isOutdated == true {
            action("Upgrade", .upgrade(target))
        }
        action("Reinstall", .reinstall(target))

        if let formula = FormulaID(entry.id) {
            if entry.installed?.isPinned == true {
                action("Unpin", .unpin(formula))
            } else {
                action("Pin", .pin(formula))
            }
        }

        snoozeItem

        Divider()

        // Destructive, and therefore confirmed. Zap is its own choice; an
        // ordinary uninstall never implies it.
        action("Uninstall…", .uninstall(target))
        if let cask = CaskID(entry.id) {
            action("Uninstall and Zap…", .zap(cask))
        }
    }

    @ViewBuilder
    private func action(_ title: String, _ command: MutationCommand) -> some View {
        Button(title) { submit(command) }
    }

    /// One entry point for every command, so the confirmation rule is applied
    /// in exactly one place rather than restated per button.
    /// Leading-dot literals (`.upgrade(target)`) cannot infer a base against a
    /// generic parameter, so the brew call sites keep this concrete overload.
    private func submit(_ command: MutationCommand) {
        submitMutation(command)
    }

    private func submit(_ command: NpmCommand) {
        submitMutation(command)
    }

    private func submitMutation(_ command: some BrewMutating) {
        if center.request(command) == nil {
            center.submit(command)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
