//
//  CaskCategoriesListView.swift
//  cellar
//

import Catalog
import SwiftUI

/// The Categories section's list pane: one row per vendored category with its
/// uncapped count — the rows the sidebar's retired CATEGORIES group used to
/// draw, moved here so the sidebar keeps its height. Selection is the category
/// id the shell already holds beside the section; the detail pane renders it.
struct CaskCategoriesListView: View {
    let catalog: CatalogStore
    @Binding var selection: String?

    @Environment(ThemeStore.self) private var theme

    private var content: CaskBrowseContent { catalog.caskBrowse }

    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                if content.categories.isEmpty {
                    Text("The catalog is still syncing.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    ForEach(content.categories) { category in
                        row(category)
                    }
                }
            }
            .padding(EdgeInsets(top: 4, leading: 12, bottom: 20, trailing: 12))
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        // The same rise the collection pages make: the toolbar row is empty on
        // cask sections, so the pane's header sits on the titlebar's baseline
        // beside the detail pane's capsule bar.
        .ignoresSafeArea(edges: .top)
        .background(Color.white.opacity(0.014))
        // Nothing picked shows the first category rather than an empty detail;
        // a survivor from a previous visit is left alone.
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: content.categories) { selectFirstIfNeeded() }
        .accessibilityIdentifier("cask-categories-pane")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(AppSection.caskCategory.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if content.categories.isEmpty == false {
                Text("\(content.categories.count)")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 26, leading: 20, bottom: 14, trailing: 16))
        .background {
            Rectangle()
                .fill(Theme.windowBackground)
                .overlay(Color.white.opacity(0.014))
        }
    }

    private func row(_ category: CaskCategorySummary) -> some View {
        let isSelected = selection == category.id
        let count = content.categoryCounts[category.id] ?? 0
        return HStack(spacing: 9) {
            Image(systemName: category.icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16)
                .foregroundStyle(isSelected ? theme.base : Color.white.opacity(0.42))
            Text(category.displayName)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textPrimary : Color.white.opacity(0.7))
            Spacer(minLength: 0)
            if count > 0 {
                Text(String(count))
                    .font(Theme.mono(10.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .frame(minWidth: 20)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.tint(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(theme.tint(0.35), lineWidth: 1)
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selection = category.id }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("cask-categories-row-\(category.id)")
    }

    private func selectFirstIfNeeded() {
        guard selection == nil else { return }
        selection = content.categories.first?.id
    }
}
