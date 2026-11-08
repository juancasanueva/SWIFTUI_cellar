//
//  CaskUpdatesView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// Which casks the Cask Updates page lists, and as what.
///
/// Reads `InstalledInventory.outdatedIDs`' own rule — `isOutdated` — so the
/// page, the Updates badge and the Installed list can never disagree; a
/// self-updating cask stays off it for the same reason it stays off them.
nonisolated enum CaskUpdatesProjection {
    /// Every outdated installed cask, in the inventory's name order.
    ///
    /// The catalog record is preferred, for its install count and category;
    /// a cask the catalog has no record for (an untrusted tap, a catalog still
    /// syncing) is drawn from its installed record instead of being dropped —
    /// an update the page hides is one the user never applies.
    static func casks(
        in inventory: InstalledInventory,
        catalog: (PackageID) -> CatalogPackage?
    ) -> [CatalogPackage] {
        inventory.packages
            .filter { $0.kind == .cask && $0.isOutdated }
            .map { catalog($0.id) ?? record(for: $0) }
    }

    private static func record(for package: InstalledPackage) -> CatalogPackage {
        CatalogPackage(
            kind: package.kind,
            name: package.name,
            displayName: package.displayName,
            desc: package.desc,
            homepage: package.homepage,
            license: nil,
            version: package.catalogVersion,
            tap: package.tap ?? "",
            dependencies: [],
            buildDependencies: [],
            dependents: [],
            caveats: nil,
            deprecated: false,
            deprecationReason: nil,
            deprecationDate: nil,
            disabled: false,
            disableReason: nil,
            disableDate: nil,
            autoUpdates: package.isSelfUpdating,
            installCount365d: nil
        )
    }
}

/// The installed casks that have an update, as the same card grid or list
/// every Discover Casks page draws — each card's verb is already Update — with
/// one Update All below that upgrades exactly the casks shown.
struct CaskUpdatesView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    /// See `CaskCollectionView.onSelectCategory`.
    var onSelectCategory: ((String) -> Void)? = nil
    /// See `CaskCollectionTopBar.shellControls`.
    var shellControls: ShellHeaderControls? = nil

    /// The grid/list choice, the same key Browse persists: the toggle carries
    /// across pages.
    @AppStorage("casks.viewMode") private var viewMode: CaskBrowseViewMode = .list

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — see `caskSearchDebounce`.
    @State private var appliedSearch = ""

    private var outdatedCasks: [CatalogPackage] {
        CaskUpdatesProjection.casks(in: installed.inventory, catalog: { catalog.package($0) })
    }

    private var displayedCasks: [CatalogPackage] {
        guard !appliedSearch.isEmpty else { return outdatedCasks }
        return CaskCollectionSearch.matches(in: outdatedCasks, query: appliedSearch)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if outdatedCasks.isEmpty {
                    note("Every installed cask is up to date.")
                } else if displayedCasks.isEmpty {
                    note("No cask update matches “\(appliedSearch)”.")
                } else {
                    CaskCollectionView(
                        casks: displayedCasks,
                        viewMode: viewMode,
                        installed: installed,
                        operations: operations,
                        assets: assets,
                        iconLoader: iconLoader,
                        onSelectCategory: onSelectCategory
                    )
                }
            }
            .frame(maxWidth: 1086)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 72, trailing: 20))
        }
        .caskCollectionTopBarPinned {
            CaskCollectionTopBar(
                title: AppSection.caskUpdates.title,
                countLabel: "\(displayedCasks.count.formatted()) casks",
                viewMode: $viewMode,
                searchText: $searchText,
                shellControls: shellControls
            )
        }
        .overlay(alignment: .bottom) {
            if !displayedCasks.isEmpty {
                updateAllButton
            }
        }
        .background(Color.white.opacity(0.014))
        .task { await assets.load() }
        .caskSearchDebounce(searchText, into: $appliedSearch)
        .accessibilityIdentifier("cask-updates-page")
    }

    /// Upgrades the casks on screen — the search narrows the batch, so the
    /// count announced and the set submitted are one projection — through the
    /// centre's bulk path, which asks before anything is enqueued.
    private var updateAllButton: some View {
        Button {
            operations.submitBulk(.upgrade, over: displayedCasks.map(\.id), in: installed.inventory)
        } label: {
            Label("Update All (\(displayedCasks.count))", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(ActionPillStyle())
        .disabled(!operations.isAvailable)
        .help(operations.unavailableGuidance ?? "Update every cask listed")
        .padding(.bottom, 16)
        .accessibilityIdentifier("cask-update-all")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
    }
}
