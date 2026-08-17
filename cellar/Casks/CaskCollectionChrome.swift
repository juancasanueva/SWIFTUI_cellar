//
//  CaskCollectionChrome.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The chrome every cask collection page shares: the capsule top bar, the
/// grid/list renderer, the list row, the search match rule, and the debounce.
/// Extracted from `CaskBrowseView` so Featured (and the pages after it) render
/// the exact same furniture instead of a copy.

/// The two ways a cask collection renders. A string raw value so `@AppStorage`
/// can hold it directly — every page reads the same "casks.viewMode" key, so
/// the choice carries across pages.
enum CaskBrowseViewMode: String {
    case grid
    case list
}

/// The capsule bar every cask page leads with: title, count, the grid/list
/// toggle, and the search field.
///
/// `accessory` is the slot a page's own controls render into — Top Charts puts
/// its period chip and sort menu there, ahead of the toggle. Generic with an
/// `EmptyView` default so every page that has none is untouched.
struct CaskCollectionTopBar<Accessory: View>: View {
    let title: String
    let countLabel: String
    @Binding var viewMode: CaskBrowseViewMode
    @Binding var searchText: String
    /// The shell's Refresh/Activity pair, drawn at the trailing edge when the
    /// page carries the whole header itself — the toolbar row shows no chrome
    /// on cask pages, so the pair lives here instead. `nil` draws nothing.
    var shellControls: ShellHeaderControls?
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        countLabel: String,
        viewMode: Binding<CaskBrowseViewMode>,
        searchText: Binding<String>,
        shellControls: ShellHeaderControls? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.countLabel = countLabel
        _viewMode = viewMode
        _searchText = searchText
        self.shellControls = shellControls
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(countLabel)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            accessory
            viewModeToggle
            searchField
            if let shellControls {
                shellControls
            }
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
        .themeCard(radius: 999)
    }

    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            modeSegment(.grid, systemImage: "square.grid.2x2")
            modeSegment(.list, systemImage: "list.bullet")
        }
        .padding(2)
        .background(Theme.controlFill, in: Capsule())
    }

    private func modeSegment(_ mode: CaskBrowseViewMode, systemImage: String) -> some View {
        let isSelected = viewMode == mode
        return Button {
            viewMode = mode
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 30, height: 22)
                .background {
                    if isSelected {
                        Capsule().fill(Theme.controlFillLoud)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cask-view-mode-\(mode.rawValue)")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            TextField("Search apps…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 240, height: 26)
        .background(Theme.controlFill, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.5))
    }
}

extension CaskCollectionTopBar where Accessory == EmptyView {
    /// The accessory-free bar every existing page already draws.
    init(
        title: String,
        countLabel: String,
        viewMode: Binding<CaskBrowseViewMode>,
        searchText: Binding<String>,
        shellControls: ShellHeaderControls? = nil
    ) {
        self.init(
            title: title,
            countLabel: countLabel,
            viewMode: viewMode,
            searchText: searchText,
            shellControls: shellControls,
            accessory: { EmptyView() }
        )
    }
}

/// The grid/list body: cards in an adaptive grid, or rows in a stack, per the
/// page's mode.
struct CaskCollectionView: View {
    let casks: [CatalogPackage]
    let viewMode: CaskBrowseViewMode
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    /// The selected window's counts, when the page ranks by one; `nil` renders
    /// every card's annual count exactly as before.
    var counts: [String: Int]? = nil
    /// Where a card's category label navigates, handed a primary category id;
    /// `nil` keeps the label the inert text it always was.
    var onSelectCategory: ((String) -> Void)? = nil

    var body: some View {
        if viewMode == .grid {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 261, maximum: 261), spacing: 14)],
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(casks) { cask in
                    CaskCardView(
                        package: cask,
                        installed: installed,
                        operations: operations,
                        assets: assets,
                        iconLoader: iconLoader,
                        counts: counts,
                        onSelectCategory: onSelectCategory
                    )
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(casks) { cask in
                    CaskListRow(
                        package: cask,
                        installed: installed,
                        operations: operations,
                        assets: assets,
                        iconLoader: iconLoader,
                        counts: counts,
                        onSelectCategory: onSelectCategory
                    )
                }
            }
        }
    }
}

/// The list-mode row: the card's facts at row density.
struct CaskListRow: View {
    let package: CatalogPackage
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    /// See `CaskCollectionView.counts`.
    var counts: [String: Int]? = nil
    /// See `CaskCollectionView.onSelectCategory`. Accepted so the collection
    /// hands both renderers the same inputs; the row draws no category label
    /// today, so it has nothing to wire the closure to yet.
    var onSelectCategory: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            CaskIconView(
                token: package.name,
                size: 30,
                isKnownToken: assets.isKnownIconToken(package.name),
                iconLoader: iconLoader
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(package.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let desc = package.desc {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(CaskPresentation.cardMeta(
                installCount: CaskPresentation.resolvedInstallCount(
                    installCount365d: package.installCount365d,
                    token: package.name,
                    counts: counts
                ),
                version: package.version
            ))
            .font(Theme.mono(9.5))
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cask-row-\(package.name)")
    }
}

/// The one search match rule every cask page filters with: case-insensitive
/// containment over token, display name, and description.
enum CaskCollectionSearch {
    static func matches(in casks: [CatalogPackage], query: String) -> [CatalogPackage] {
        let query = query.lowercased()
        return casks.filter { cask in
            cask.name.lowercased().contains(query)
                || cask.displayName.lowercased().contains(query)
                || (cask.desc?.lowercased().contains(query) ?? false)
        }
    }
}

extension View {
    /// Pins a page's top bar above its scrolling content: the bar sits in a
    /// top safe-area inset, so the cards scroll beneath it while it stays put.
    /// The backdrop reaches up through the transparent toolbar row, so scrolled
    /// content never bleeds behind the window title either.
    func caskCollectionTopBarPinned(@ViewBuilder _ bar: () -> some View) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            bar()
                .frame(maxWidth: 1086)
                .frame(maxWidth: .infinity)
                // Top 16 mirrors the gap below the bar: its own 10 bottom
                // padding plus the content's 6 top padding.
                .padding(EdgeInsets(top: 16, leading: 20, bottom: 10, trailing: 20))
                .background {
                    Rectangle()
                        .fill(Theme.windowBackground)
                        .overlay(Color.white.opacity(0.014))
                }
        }
        // The page owns its whole header: with the toolbar row empty on cask
        // sections, the bar rises through the top safe area so the capsule
        // sits on the traffic lights' and sidebar toggle's own baseline.
        .ignoresSafeArea(edges: .top)
    }

    /// `searchText` debounced 200 ms into `applied` — typing filters a few
    /// thousand cards, so the filter runs per pause rather than per keystroke.
    func caskSearchDebounce(_ searchText: String, into applied: Binding<String>) -> some View {
        task(id: searchText) {
            guard !searchText.isEmpty else {
                applied.wrappedValue = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            applied.wrappedValue = searchText
        }
    }
}
