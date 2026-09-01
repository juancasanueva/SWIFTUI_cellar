//
//  FormulaBrowseView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The formula storefront: the cask Browse's furniture on the other kind — a
/// house pick and the Most Popular shelf. No category shelves and no Recently
/// Added, because both lean on cask-mined data with no formula equivalent.
///
/// Presentation only: what is eligible and what leads is settled in
/// `CellarCore`'s `FormulaBrowseProjection` and asserted there; this view
/// renders `catalog.formulaBrowse` and submits verbs.
struct FormulaBrowseView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    @Binding var section: AppSection
    var shellControls: ShellHeaderControls? = nil

    /// The grid/list choice, the formula pages' own key — a formula list and a
    /// cask grid are different reading modes, so the choice does not cross.
    @AppStorage("formulae.viewMode") private var viewMode: CaskBrowseViewMode = .list

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — see `caskSearchDebounce`.
    @State private var appliedSearch = ""

    private var content: FormulaBrowseContent { catalog.formulaBrowse }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if content == .empty {
                    CaskCatalogSyncingNote()
                } else if appliedSearch.isEmpty {
                    if let housePick = content.housePick {
                        heroCard(for: housePick)
                    }
                    shelfView
                } else {
                    searchResults
                }
            }
            .frame(maxWidth: 1086)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 48, trailing: 20))
        }
        .caskCollectionTopBarPinned {
            CaskCollectionTopBar(
                title: "Browse",
                countLabel: "\(content.formulaCount.formatted()) formulae",
                viewMode: $viewMode,
                searchText: $searchText,
                shellControls: shellControls
            )
        }
        .background(Color.white.opacity(0.014))
        .caskSearchDebounce(searchText, into: $appliedSearch)
        .accessibilityIdentifier("formula-browse-page")
    }

    // MARK: - Hero

    private func heroCard(for housePick: CatalogPackage) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("✷ HOUSE PICK")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(2)
                    .foregroundStyle(theme.base)
                Text(housePick.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let desc = housePick.desc {
                    Text(desc)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(2)
                }
                HStack(spacing: 14) {
                    heroAction(for: housePick)
                    Text(CaskPresentation.heroMeta(
                        installCount: housePick.installCount365d,
                        version: housePick.version,
                        categoryName: nil
                    ))
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.well)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 0.5)
                    )
                CaskIconView(
                    token: housePick.name,
                    size: 96,
                    isKnownToken: false,
                    iconLoader: iconLoader,
                    loadsRemote: false
                )
            }
            .frame(width: 104, height: 104)
        }
        .padding(EdgeInsets(top: 22, leading: 28, bottom: 22, trailing: 28))
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .themeCard(fill: Theme.cardFillLoud, radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("formula-house-pick")
    }

    @ViewBuilder
    private func heroAction(for housePick: CatalogPackage) -> some View {
        // In-flight first: inert progress feedback in the verb's place, so
        // the hero cannot submit the same package a second time mid-flight.
        if let busy = operations.activeMutation(naming: housePick.id) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(busy.progressLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(Theme.controlFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.5))
            .accessibilityIdentifier("formula-hero-busy")
        } else if let target = PackageTarget(housePick.id) {
            let installedPackage = installed.inventory.package(housePick.id)
            if let installedPackage, installedPackage.isOutdated {
                heroButton("Update", fill: theme.tint(0.22)) { submit(.upgrade(target)) }
            } else if installedPackage != nil {
                Text("● Installed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.successText)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(Theme.successTint(0.15), in: Capsule())
            } else {
                heroButton("↓ Install", fill: theme.tint(0.12)) { submit(.install(target)) }
            }
        }
    }

    private func heroButton(
        _ label: String,
        fill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.light)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.tint(0.35), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!operations.isAvailable)
        .accessibilityIdentifier("formula-hero-install")
    }

    // MARK: - The one shelf

    private var shelfView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // The cask shelves' header idiom: the ranked shelf reuses its
                // sidebar section's icon.
                Image(systemName: AppSection.formulaTopCharts.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Most Popular")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Button("View All") { section = .formulaTopCharts }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.base)
                    .accessibilityIdentifier("formula-view-all-\(AppSection.formulaTopCharts.rawValue)")
            }
            formulaeView(content.mostPopular)
        }
    }

    private func formulaeView(_ formulae: [CatalogPackage]) -> some View {
        CaskCollectionView(
            casks: formulae,
            viewMode: viewMode,
            installed: installed,
            operations: operations,
            assets: assets,
            iconLoader: iconLoader,
            remoteIcons: false
        )
    }

    // MARK: - Search

    private var searchMatches: [CatalogPackage] {
        CaskCollectionSearch.matches(in: content.allByPopularity, query: appliedSearch)
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Results")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(searchMatches.count.formatted())")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            if searchMatches.isEmpty {
                Text("No formula matches “\(appliedSearch)”.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                formulaeView(searchMatches)
            }
        }
    }

    @Environment(ThemeStore.self) private var theme

    /// The `PackageDetailView` idiom, verbatim: the confirmation rule is
    /// applied in exactly one place.
    private func submit(_ command: MutationCommand) {
        if operations.request(command) == nil {
            operations.submit(command)
        }
    }
}
