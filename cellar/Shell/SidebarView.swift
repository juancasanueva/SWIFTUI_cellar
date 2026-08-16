//
//  SidebarView.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SecurityKit
import SwiftUI

/// The sidebar column: four labelled groups and a Settings footer, drawn on
/// the system sidebar material `NavigationSplitView` provides — which is what
/// buys the native toggle, the collapse animation, and the window's rounded
/// corners for free.
///
/// Every count badge reads a store the shell already owns; the sidebar keeps no
/// state of its own beyond the binding it is handed.
struct SidebarView: View {
    @Binding var section: AppSection
    let installed: InstalledStore
    let metadata: MetadataStore
    let services: ServicesStore
    let security: SecurityStore
    let taps: TapStore
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // The traffic lights and the native sidebar toggle live in the
            // column's toolbar strip; the top safe area already covers it.
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(AppSection.sidebarGroups, id: \.title) { group in
                        VStack(spacing: 1) {
                            Text(group.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .kerning(0.6)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.white.opacity(0.3))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(EdgeInsets(top: 2, leading: 8, bottom: 6, trailing: 8))
                            ForEach(group.sections) { item in
                                row(item)
                            }
                        }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 10, bottom: 14, trailing: 10))
            }
            VStack(spacing: 1) {
                ForEach(AppSection.sidebarFooter) { item in
                    row(item)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 12, trailing: 10))
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.separator).frame(height: 0.5)
            }
        }
    }

    private func row(_ item: AppSection) -> some View {
        let isSelected = section == item
        // A tappable container rather than a `Button`: a Button folds its label
        // into one element, and the UI tests click sections by their visible
        // title (`staticTexts["Taps"]`), so the texts must stay reachable.
        return HStack(spacing: 9) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 15)
                    .foregroundStyle(isSelected ? theme.base : Color.white.opacity(0.42))
                Text(item.sidebarTitle)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Color.white.opacity(0.7))
                Spacer(minLength: 0)
                if let badge = badge(for: item) {
                    Text(badge.count)
                        .font(Theme.mono(10.5, weight: .semibold))
                        .foregroundStyle(badge.foreground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .frame(minWidth: 20)
                        .background(badge.background, in: Capsule())
                }
            }
        .padding(.horizontal, 12)
        .frame(height: 31)
        .background {
            if isSelected {
                Capsule()
                    .fill(theme.tint(0.14))
                    .overlay(Capsule().strokeBorder(theme.tint(0.35), lineWidth: 1))
            }
        }
        .contentShape(Capsule())
        .onTapGesture { section = item }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sidebar-\(item.rawValue)")
    }

    // MARK: - Badges

    private struct Badge {
        let count: String
        let background: Color
        let foreground: Color
    }

    /// Which rows carry a count, and in which of the design's three tones:
    /// neutral, accent-warn (updates), danger (security findings).
    private func badge(for item: AppSection) -> Badge? {
        func neutral(_ count: Int) -> Badge? {
            count > 0
                ? Badge(
                    count: String(count),
                    background: Color.white.opacity(0.08),
                    foreground: Color.white.opacity(0.5)
                )
                : nil
        }
        switch item {
        case .installed:
            return neutral(installed.inventory.packages.count)
        case .favorites:
            return neutral(favoritesCount)
        case .updates:
            let count = outdatedCount
            guard count > 0 else { return nil }
            return Badge(count: String(count), background: theme.tint(0.22), foreground: theme.light)
        case .services:
            return neutral(runningServicesCount)
        case .security:
            let count = vulnerableCount
            guard count > 0 else { return nil }
            return Badge(
                count: String(count),
                background: Theme.dangerTint(0.22),
                foreground: Theme.dangerText
            )
        case .taps:
            return neutral(taps.inventory.taps.count)
        case .health:
            // Its own arm — the source scanner keys on `case .health` to prove
            // this switch is exhaustive over `AppSection` with no default.
            return nil
        case .home, .discover, .browse, .cleanup, .brewfile, .history, .settings:
            // Exhaustive on purpose: a `default:` here is what would let a new
            // section ship with its badge silently absent.
            return nil
        }
    }

    private var favoritesCount: Int {
        guard metadata.availability.isAvailable else { return 0 }
        return installed.inventory.packages
            .filter { metadata.snapshot[$0.id]?.isFavorite == true }
            .count
    }

    private var outdatedCount: Int {
        installed.inventory.packages.filter(\.isOutdated).count
    }

    private var runningServicesCount: Int {
        services.services.filter { $0.status == .started }.count
    }

    private var vulnerableCount: Int {
        security.coverages.values.reduce(0) { $0 + $1.vulnerable }
    }
}
