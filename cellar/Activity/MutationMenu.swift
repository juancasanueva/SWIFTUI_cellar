//
//  MutationMenu.swift
//  cellar
//

import BrewClient
import Catalog
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

    /// The entry's identity, proven safe to put in argv.
    ///
    /// `nil` only for a name brew could read as an option, in which case every
    /// package-naming affordance is simply absent — an unvalidated command is
    /// not representable, so there is nothing to disable (design D9, PM9).
    private var target: PackageTarget? { PackageTarget(entry.id) }

    var body: some View {
        Menu {
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
        } label: {
            Label("Package actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!center.isAvailable)
        .help(center.unavailableGuidance ?? "Install, upgrade or remove \(entry.displayName)")
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
    private func submit(_ command: MutationCommand) {
        if center.request(command) == nil {
            center.submit(command)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
