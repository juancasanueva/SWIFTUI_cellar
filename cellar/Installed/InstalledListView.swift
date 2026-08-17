//
//  InstalledListView.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SwiftUI

enum InstalledSelection {
    nonisolated static func adopting(
        _ candidate: PackageID?,
        into current: Set<PackageID>,
        available: Set<PackageID>
    ) -> Set<PackageID> {
        guard let candidate, available.contains(candidate) else { return current }
        return current.union([candidate])
    }
}

/// What this machine has installed.
///
/// The list is driven by the inventory, never by the catalog: everything a row
/// shows came out of the one `brew info --installed` snapshot, and the catalog
/// only decorates. A cold, empty or poisoned catalog therefore costs a
/// description and an install count, never a row (design D5).
/// Which slice of the inventory this list is standing in front of.
///
/// `.favorites` and `.updates` are the design's sidebar promotions of the two
/// existing lenses — the same projections, preset rather than re-derived.
enum InstalledLens {
    case all
    case favorites
    case updates
}

struct InstalledListView: View {
    let installed: InstalledStore
    let catalog: CatalogStore
    let operations: OperationCenter
    let metadata: MetadataStore
    /// The cask artwork pipeline; `nil` — a preview, say — keeps the letter
    /// tile for every row (see `PackageIconTile`).
    var assets: CaskBrowseAssets?
    var iconLoader: CaskIconLoader?
    @Binding var selection: PackageID?
    var lens: InstalledLens = .all

    /// Off by default: a machine with 160 packages installed usually has ~40
    /// the user chose and 120 that came along for the ride.
    @State private var includeDependencies = false
    /// The kind narrowing, `nil` for both — the Search catalog's three-way
    /// choice, applied here as a display filter like the in-pane query.
    @State private var kind: PackageKind?

    /// The native multi-select binding. A `Set` cannot carry order.
    @State private var selected: Set<PackageID> = []
    /// The ordered truth, maintained beside it — and the **only** thing the bulk
    /// bar, the confirmation and the submission ever read (design D8).
    @State private var order: [PackageID] = []

    /// A local, name-and-description filter over the projected entries — the
    /// design's in-pane search. It narrows what is shown and nothing else.
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            PaneSearchField(text: $query, prompt: "Filter…")
                .padding(EdgeInsets(top: 11, leading: 13, bottom: 0, trailing: 13))
            InstalledFilterBar(
                kind: $kind,
                includeDependencies: $includeDependencies,
                upgradableCount: upgradableIDs.count,
                state: installed.state
            )
            if !bulk.isEmpty {
                BulkActionBar(
                    selection: bulk,
                    operations: operations,
                    inventory: installed.inventory,
                    // Derived from the same entries and the same metadata lookup
                    // the four mutation verbs are, so every count on the bar comes
                    // out of one projection (II14).
                    snooze: bulkSnooze,
                    metadata: metadata
                )
            } else if !upgradableIDs.isEmpty {
                bulkUpgradeBar
            }
            Divider()

            List(selection: $selected) {
                if !sections.outdated.isEmpty {
                    Section("Outdated") {
                        ForEach(sections.outdated) { entry in
                            row(entry)
                        }
                    }
                }
                if !sections.selfUpdating.isEmpty {
                    // Separate on purpose: these apps update themselves, so
                    // presenting them as outdated would ask the user to fix
                    // something that is not broken (product decision Q3).
                    Section("Updates itself") {
                        ForEach(sections.selfUpdating) { entry in
                            row(entry)
                        }
                    }
                }
                // Empty under the Updates lens, whose entries are all outdated
                // — a bare header there announces a section that cannot fill.
                if !sections.rest.isEmpty {
                    Section(includeDependencies ? "All packages" : "Installed on request") {
                        ForEach(sections.rest) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("installed-list")
            .overlay {
                if entries.isEmpty {
                    InstalledEmptyState(state: installed.state, lens: lens)
                }
            }
            .onChange(of: selected) { _, current in
                reconcileOrder(with: current)
            }
            .onChange(of: selection) { _, current in
                adoptExternalSelection(current)
            }
            .onChange(of: entries) { _, _ in
                // A package that has left the inventory leaves the selection at
                // the next refresh, rather than producing an operation for
                // something the app no longer lists (II13 sc3).
                let live = Set(entries.map(\.id))
                selected = selected.intersection(live)
                adoptExternalSelection(selection)
                dropForeignSelection()
            }
        }
        // No manual refresh control: the inventory refreshes at launch, on
        // activation, and within the quiet window of any external change, so a
        // button here would only ever duplicate work already scheduled.
        .background(Color.white.opacity(0.014))
        // The manifest gate behind each row's icon lookup; idempotent, so the
        // Discover pages and this list can all ask (see `CaskBrowseAssets`).
        .task { await assets?.load() }
        .onAppear {
            adoptExternalSelection(selection)
            dropForeignSelection()
        }
    }

    /// Clears a detail selection this lens does not contain.
    ///
    /// The selection is shared across sections so "Show in Installed" can hand
    /// one over — but a package selected elsewhere must not keep a detail pane
    /// standing beside an Updates or Favorites list that does not list it.
    /// `.all` never drops: it is the handoff's destination, and its entries may
    /// legitimately be empty mid-refresh.
    private func dropForeignSelection() {
        guard lens != .all,
              let current = selection,
              !entries.contains(where: { $0.id == current })
        else { return }
        selection = nil
    }

    private func row(_ entry: PackageEntry) -> some View {
        InstalledRow(
            entry: entry,
            operations: operations,
            metadata: metadata,
            showsFavoriteHeart: lens == .favorites,
            assets: assets,
            iconLoader: iconLoader
        )
            .tag(entry.id)
            .themedListSelection(isSelected: selected.contains(entry.id))
    }

    /// Keeps `order` a faithful, ordered view of `selected`.
    ///
    /// Two steps, and the split is the whole point. Deselections are removed
    /// **in place**, so everything still selected keeps its relative order. New
    /// ids are appended in **displayed-row order**, never in `Set` iteration
    /// order — which is unstable across launches and would make the submission
    /// sequence non-reproducible. A single click adds exactly one id, so click
    /// order is click order; a shift-click or Select All adds many at once, and
    /// those arrive as the list shows them.
    ///
    /// It reads `sections.displayed` rather than `entries`, which is what makes
    /// the second sentence true: `entries` is flat inventory order, so a bulk
    /// add used to enter — and submit — in an order the user never saw (II13,
    /// design D9).
    private func reconcileOrder(with current: Set<PackageID>) {
        order.removeAll { !current.contains($0) }
        let added = sections.displayed.map(\.id).filter { current.contains($0) && !order.contains($0) }
        order.append(contentsOf: added)
        // The detail column follows a single selection only: two selected
        // packages have no one package to show.
        selection = order.count == 1 ? order.first : nil
    }

    /// Adds a valid selection handed in by another app section without treating
    /// a `nil` detail selection as a request to discard a legitimate bulk set.
    private func adoptExternalSelection(_ candidate: PackageID?) {
        let adopted = InstalledSelection.adopting(
            candidate,
            into: selected,
            available: Set(entries.map(\.id))
        )
        guard adopted != selected else { return }
        selected = adopted
    }

    /// The two bulk entry points offered when nothing is selected.
    ///
    /// "Upgrade outdated" fans out into one operation per package, so each gets
    /// its own log, cancel and terminal outcome; "Upgrade all" is the single
    /// bare `brew upgrade` with brew's own defaults. Both refuse to name a
    /// pinned package, and neither unpins anything (package-mutation PM2).
    ///
    /// The label counts `upgradableIDs` and the button submits `upgradableIDs`
    /// — one projection, read twice, so the number announced and the set
    /// submitted cannot drift apart (installed-inventory II14).
    private var bulkUpgradeBar: some View {
        HStack(spacing: 8) {
            Button("Upgrade outdated (\(upgradableIDs.count))") {
                operations.submitUpgrades(for: upgradableIDs, in: installed.inventory)
            }
            .buttonStyle(ActionPillStyle())
            Button("Upgrade all") {
                operations.submit(.upgradeAll)
            }
            .buttonStyle(ActionPillStyle())
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

    /// `nil` when there is no metadata to compose, which is exactly what makes
    /// a cold or unavailable store degrade to M2-1 behaviour with no branch.
    private var lookup: MetadataLookup? {
        metadata.availability.isAvailable ? metadata.snapshot.lookup : nil
    }

    private var entries: [PackageEntry] {
        let base = browse.entries(
            includingDependencies: includeDependencies,
            catalogLookup: { catalog.package($0) },
            metadata: lookup,
            favoritesOnly: lens == .favorites
        )
        var narrowed = base
        if let kind {
            narrowed = narrowed.filter { $0.id.kind == kind }
        }
        if lens == .updates {
            let outdated = browse.outdatedIDs(metadata: lookup)
            narrowed = narrowed.filter { outdated.contains($0.id) }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.isEmpty == false else { return narrowed }
        return narrowed.filter {
            $0.id.name.lowercased().contains(trimmed)
                || ($0.desc?.lowercased().contains(trimmed) ?? false)
        }
    }

    /// The one projection the label, this section, the badge and the submission
    /// all read.
    private var upgradableIDs: [PackageID] {
        browse.upgradableIDs(includingDependencies: includeDependencies, metadata: lookup)
    }

    private var bulk: BulkSelection {
        BulkSelection(selection: order, entries: entries, metadata: lookup)
    }

    /// The snooze half of the same selection.
    ///
    /// A separate value rather than a fifth `BulkSelection.Action`, because a
    /// snooze produces no `MutationCommand` and a case that produced none would be
    /// a silent no-op inside the mutation spine (design HD11).
    private var bulkSnooze: BulkSnoozeSelection {
        BulkSnoozeSelection(selection: order, entries: entries, metadata: lookup)
    }

    /// The one projection the three sections and `reconcileOrder` all read, so
    /// what is rendered and what a bulk selection enters cannot drift apart.
    ///
    /// Snoozed packages leave the outdated section — and the count above it —
    /// through the same set, so the two cannot disagree (II12). A snooze never
    /// removes a package from the list: it suppresses a badge and a count, and
    /// hiding the row would take the package out of reach entirely (LPM5 sc5,
    /// II12 sc4).
    private var sections: InstalledSections {
        InstalledSections(entries: entries, outdatedIDs: browse.outdatedIDs(metadata: lookup))
    }
}

#Preview {
    @Previewable @State var selection: PackageID?
    return InstalledListView(
        installed: InstalledStore(),
        catalog: CatalogStore(directory: FileManager.default.temporaryDirectory),
        operations: OperationCenter(),
        metadata: MetadataStore(container: nil),
        selection: $selection
    )
}
