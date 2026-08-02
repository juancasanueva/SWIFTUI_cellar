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
            Divider()

            List(selection: $selection) {
                if !outdated.isEmpty {
                    Section("Outdated") {
                        ForEach(outdated) { entry in
                            InstalledRow(entry: entry).tag(entry.id)
                        }
                    }
                }
                if !selfUpdating.isEmpty {
                    // Separate on purpose: these apps update themselves, so
                    // presenting them as outdated would ask the user to fix
                    // something that is not broken (product decision Q3).
                    Section("Updates itself") {
                        ForEach(selfUpdating) { entry in
                            InstalledRow(entry: entry).tag(entry.id)
                        }
                    }
                }
                Section(includeDependencies ? "All packages" : "Installed on request") {
                    ForEach(rest) { entry in
                        InstalledRow(entry: entry).tag(entry.id)
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
        selection: $selection
    )
}
