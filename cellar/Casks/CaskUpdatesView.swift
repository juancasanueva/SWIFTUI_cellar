//
//  CaskUpdatesView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// What the self-updating scan is keyed on: a new inventory or the toggle
/// flipping reruns it, nothing else does.
private struct SelfUpdatingScan: Equatable {
    let inventory: InstalledInventory
    let isEnabled: Bool
}

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
    ///
    /// `selfUpdatingBehind` opts the self-updating casks in: `nil` keeps them
    /// off, as the outdated set does; otherwise a self-updating cask joins
    /// when the closure says its app is behind — judged from the app on disk
    /// (`CaskAppVersion`), because brew's own record goes stale the moment the
    /// app updates itself.
    static func casks(
        in inventory: InstalledInventory,
        catalog: (PackageID) -> CatalogPackage?,
        selfUpdatingBehind: ((InstalledPackage) -> Bool)? = nil
    ) -> [CatalogPackage] {
        inventory.packages
            .filter { package in
                guard package.kind == .cask else { return false }
                if package.isOutdated { return true }
                guard package.isSelfUpdating, let selfUpdatingBehind else { return false }
                return selfUpdatingBehind(package)
            }
            .map { catalog($0.id) ?? record(for: $0) }
    }

    /// Whether a self-updating cask's app is behind its published version:
    /// the app's own reported version when it can be read, otherwise brew's
    /// record — the same comparison `hasNewerVersion` makes.
    static func isSelfUpdatingBehind(_ package: InstalledPackage, appURL: URL?) -> Bool {
        if let appURL {
            let versions = CaskAppVersion.versions(ofAppAt: appURL)
            if let behind = CaskAppVersion.isBehind(
                shortVersion: versions.short,
                bundleVersion: versions.bundle,
                catalogVersion: package.catalogVersion
            ) {
                return behind
            }
        }
        return package.hasNewerVersion
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

    /// Off by default: Homebrew leaves apps that update themselves alone
    /// unless asked, and so does this page.
    @AppStorage("casks.updates.includeSelfUpdating") private var includeSelfUpdating = false

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — see `caskSearchDebounce`.
    @State private var appliedSearch = ""
    /// The self-updating casks whose app on disk is behind, read off the main
    /// actor once per inventory — reading every `Info.plist` per render would
    /// put disk work on every keystroke.
    @State private var selfUpdatingBehind: Set<PackageID> = []

    private var outdatedCasks: [CatalogPackage] {
        CaskUpdatesProjection.casks(
            in: installed.inventory,
            catalog: { catalog.package($0) },
            selfUpdatingBehind: includeSelfUpdating ? { selfUpdatingBehind.contains($0.id) } : nil
        )
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
                        onSelectCategory: onSelectCategory,
                        // A self-updating cask's card would otherwise offer
                        // Open: it is never `isOutdated`. Every cask here is
                        // listed *because* it has an update, so each earns the
                        // verb — a named upgrade brew performs without --greedy.
                        offersUpdate: Set(displayedCasks.map(\.id))
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
            ) {
                selfUpdatingToggle
            }
        }
        .overlay(alignment: .bottom) {
            if !displayedCasks.isEmpty {
                updateAllButton
            }
        }
        .background(Color.white.opacity(0.014))
        .task { await assets.load() }
        .caskSearchDebounce(searchText, into: $appliedSearch)
        .task(id: SelfUpdatingScan(inventory: installed.inventory, isEnabled: includeSelfUpdating)) {
            guard includeSelfUpdating else { return }
            selfUpdatingBehind = await scanSelfUpdating()
        }
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

    private var selfUpdatingToggle: some View {
        Toggle(isOn: $includeSelfUpdating) {
            Text("Include Self-Updating Apps")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .toggleStyle(.checkbox)
        .fixedSize()
        .help("Also list apps that update themselves when the copy on disk is behind the latest version.")
        .accessibilityIdentifier("cask-updates-include-self-updating")
    }

    /// Resolves each self-updating cask's app on the main actor (the lookup
    /// reads the shell's stores), then reads the bundles off it.
    private func scanSelfUpdating() async -> Set<PackageID> {
        let candidates = installed.inventory.packages
            .filter { $0.kind == .cask && $0.isSelfUpdating && !$0.isOutdated }
            .map { ($0, iconLoader.installedAppURL(for: $0.name)) }
        return await Self.behind(candidates)
    }

    @concurrent
    private static func behind(_ candidates: [(InstalledPackage, URL?)]) async -> Set<PackageID> {
        Set(candidates
            .filter { CaskUpdatesProjection.isSelfUpdatingBehind($0.0, appURL: $0.1) }
            .map(\.0.id))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
    }
}
