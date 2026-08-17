//
//  CaskCardView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// One cask as a 261×176 storefront card: artwork, name, category, two lines
/// of description, the meta line, and the one verb that fits its state.
struct CaskCardView: View {
    let package: CatalogPackage
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    /// See `CaskCollectionView.counts`.
    var counts: [String: Int]? = nil
    /// See `CaskCollectionView.onSelectCategory`.
    var onSelectCategory: ((String) -> Void)? = nil

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(package.desc ?? " ")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textBody)
                .lineLimit(2)
                .frame(minHeight: 30, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            Spacer(minLength: 0)
            actionRow
        }
        .padding(14)
        .frame(width: 261, height: 176, alignment: .top)
        .themeCard(radius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cask-card-\(package.name)")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            CaskIconView(
                token: package.name,
                size: 44,
                isKnownToken: assets.isKnownIconToken(package.name),
                iconLoader: iconLoader
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(package.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                // The Discover rule kept catalog-adjacent text inert; the
                // category pages amend it. On a page that can navigate the
                // label is a link to the primary category's page, styled as
                // the same quiet text; without the closure — or for an
                // unmapped token — it stays exactly the inert `Text` it was.
                if let category = assets.primaryCategoryName(for: package.name) {
                    if let onSelectCategory,
                       let categoryID = assets.primaryCategoryID(for: package.name) {
                        Button {
                            onSelectCategory(categoryID)
                        } label: {
                            categoryLabel(category)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .accessibilityIdentifier("cask-card-category-\(package.name)")
                    } else {
                        categoryLabel(category)
                    }
                }
            }
            Spacer(minLength: 0)
            CaskInfoButton(package: package, installed: installed, assets: assets)
        }
        .frame(height: 48, alignment: .top)
    }

    /// The label's one look, link or not.
    private func categoryLabel(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10.5))
            .foregroundStyle(theme.base)
            .lineLimit(1)
    }

    /// One verb by `CaskActionState`'s priority — update, installed, install —
    /// and **no** affordance at all for an identity brew cannot target.
    @ViewBuilder
    private var actionRow: some View {
        switch CaskActionState.resolve(package, installed: installed) {
        case .update(let target):
            HStack(spacing: 8) {
                // Louder than Install: an update is the verb that most often
                // brings a user here, the sidebar badge's own rule.
                actionButton("Update", identifier: "cask-update-\(package.name)", fill: theme.tint(0.22)) {
                    submit(.upgrade(target))
                }
                uninstallButton(target)
            }
        case .installed(let target):
            HStack(spacing: 8) {
                // Not a button: the state itself asks for nothing further.
                Text("● Installed")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.successText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        Theme.successTint(0.15),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                uninstallButton(target)
            }
        case .install(let target):
            actionButton("↓ Install", identifier: "cask-install-\(package.name)") {
                submit(.install(target))
            }
        case nil:
            EmptyView()
        }
    }

    /// The destructive verb beside whichever state an installed cask shows.
    /// Routed through the same `submit` idiom, so the operation center's
    /// uninstall confirmation still fronts it.
    private func uninstallButton(_ target: PackageTarget) -> some View {
        Button {
            submit(.uninstall(target))
        } label: {
            Text("Uninstall")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.dangerText)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    Theme.dangerTint(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.dangerTint(0.35), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!operations.isAvailable)
        .accessibilityIdentifier("cask-uninstall-\(package.name)")
    }

    private func actionButton(
        _ label: String,
        identifier: String,
        fill: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme.light)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    fill ?? theme.tint(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.tint(0.35), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!operations.isAvailable)
        .accessibilityIdentifier(identifier)
    }

    /// The `PackageDetailView` idiom, verbatim: the confirmation rule is
    /// applied in exactly one place.
    private func submit(_ command: MutationCommand) {
        if operations.request(command) == nil {
            operations.submit(command)
        }
    }
}
