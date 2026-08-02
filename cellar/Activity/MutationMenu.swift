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

    var body: some View {
        Menu {
            if entry.isInstalled {
                installedActions
            } else {
                action("Install", .install(entry.id))
            }
            Divider()
            Button("Copy install command") {
                copy(MutationCommand.install(entry.id).displayCommand)
            }
        } label: {
            Label("Package actions", systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .disabled(!center.isAvailable)
        .help(center.unavailableGuidance ?? "Install, upgrade or remove \(entry.displayName)")
    }

    @ViewBuilder
    private var installedActions: some View {
        if entry.installed?.isOutdated == true {
            action("Upgrade", .upgrade(entry.id))
        }
        action("Reinstall", .reinstall(entry.id))

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
        action("Uninstall…", .uninstall(entry.id))
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
