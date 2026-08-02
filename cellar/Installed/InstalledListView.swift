//
//  InstalledListView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// What this machine has installed.
///
/// The list is driven by the inventory, never by the catalog: everything a row
/// shows came out of the one `brew info --installed` snapshot, and the catalog
/// only decorates. A cold, empty or poisoned catalog therefore costs a
/// description and an install count, never a row (design D5).
struct InstalledListView: View {
    let installed: InstalledStore
    let catalog: CatalogStore
    let operations: OperationCenter
    @Binding var selection: PackageID?

    /// Off by default: a machine with 160 packages installed usually has ~40
    /// the user chose and 120 that came along for the ride.
    @State private var includeDependencies = false

    var body: some View {
        VStack(spacing: 0) {
            InstalledFilterBar(
                includeDependencies: $includeDependencies,
                outdatedCount: installed.inventory.outdatedCount,
                state: installed.state
            )
            if !outdated.isEmpty {
                bulkUpgradeBar
            }
            Divider()

            List(selection: $selection) {
                if !outdated.isEmpty {
                    Section("Outdated") {
                        ForEach(outdated) { entry in
                            InstalledRow(entry: entry, operations: operations).tag(entry.id)
                        }
                    }
                }
                if !selfUpdating.isEmpty {
                    // Separate on purpose: these apps update themselves, so
                    // presenting them as outdated would ask the user to fix
                    // something that is not broken (product decision Q3).
                    Section("Updates itself") {
                        ForEach(selfUpdating) { entry in
                            InstalledRow(entry: entry, operations: operations).tag(entry.id)
                        }
                    }
                }
                Section(includeDependencies ? "All packages" : "Installed on request") {
                    ForEach(rest) { entry in
                        InstalledRow(entry: entry, operations: operations).tag(entry.id)
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    InstalledEmptyState(state: installed.state)
                }
            }
        }
        // No manual refresh control: the inventory refreshes at launch, on
        // activation, and within the quiet window of any external change, so a
        // button here would only ever duplicate work already scheduled.
        .navigationTitle(AppSection.installed.title)
    }

    /// The two bulk entry points.
    ///
    /// "Upgrade outdated" fans out into one operation per package, so each gets
    /// its own log, cancel and terminal outcome; "Upgrade all" is the single
    /// bare `brew upgrade` with brew's own defaults. Both refuse to name a
    /// pinned package, and neither unpins anything (package-mutation PM2).
    private var bulkUpgradeBar: some View {
        HStack(spacing: 8) {
            Button("Upgrade outdated (\(outdated.count))") {
                operations.submitUpgradesForOutdated(in: installed.inventory)
            }
            Button("Upgrade all") {
                operations.submit(.upgradeAll)
            }
            Spacer(minLength: 0)
            CopyCommandButton(text: MutationCommand.upgradeAll.displayCommand)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .disabled(!operations.isAvailable)
        .help(operations.unavailableGuidance ?? "Upgrade outdated packages")
    }

    // MARK: - Sections

    private var browse: InstalledBrowse {
        InstalledBrowse(inventory: installed.inventory, isAvailable: installed.absence == nil)
    }

    private var entries: [PackageEntry] {
        browse.entries(
            includingDependencies: includeDependencies,
            catalogLookup: { catalog.package($0) }
        )
    }

    private var outdated: [PackageEntry] {
        entries.filter { $0.installed?.isOutdated == true }
    }

    private var selfUpdating: [PackageEntry] {
        entries.filter { $0.installed?.hasNewerVersion == true }
    }

    private var rest: [PackageEntry] {
        entries.filter {
            $0.installed?.isOutdated != true && $0.installed?.hasNewerVersion != true
        }
    }
}

#Preview {
    @Previewable @State var selection: PackageID?
    return InstalledListView(
        installed: InstalledStore(),
        catalog: CatalogStore(directory: FileManager.default.temporaryDirectory),
        operations: OperationCenter(),
        selection: $selection
    )
}
