//
//  PackageRow.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// One package in the Browse list.
///
/// Deprecated and disabled packages stay in the list and carry a badge instead
/// of disappearing: a user searching for a package that was just deprecated
/// deserves to be told so, not to be told nothing (package-search PS4).
///
/// The row takes a `PackageEntry` rather than a `CatalogPackage` because a
/// filtered list can contain a package this machine has installed that the
/// catalog has never heard of — a third-party tap — and that row must render in
/// full rather than vanish (installed-inventory II7).
struct PackageRow: View {
    let entry: PackageEntry
    /// Measured size on disk, when this machine has the package and the disk
    /// scan has answered for it. The catalog publishes no size, so a row that
    /// is not installed has nothing honest to show here and keeps the yearly
    /// install count instead.
    var sizeOnDisk: Int64?
    /// The cask artwork pipeline; `nil` — a preview, say — keeps the letter
    /// tile for every row (see `PackageIconTile`).
    var assets: CaskBrowseAssets?
    var iconLoader: CaskIconLoader?

    var body: some View {
        HStack(spacing: 10) {
            PackageIconTile(id: entry.id, assets: assets, iconLoader: iconLoader)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)
                    KindTag(kind: entry.id.kind)
                    if entry.isInstalled {
                        // A pill, not an icon: the row already speaks in chips
                        // (CASK, UPDATE), so its states read in chips too.
                        statusPill(
                            "Installed",
                            background: Theme.successTint(0.16),
                            foreground: Theme.successText
                        )
                    }
                    // The same pill the Installed and Updates lists draw, so
                    // "this has an update" reads identically everywhere.
                    if let installed = entry.installed, installed.isOutdated {
                        UpdateTag(nextVersion: installed.catalogVersion)
                    }
                    ForEach(entry.catalog?.badges ?? [], id: \.self) { badge in
                        statusPill(
                            badge.label,
                            background: Color.orange.opacity(0.16),
                            foreground: Color.orange
                        )
                    }
                    Spacer(minLength: 0)
                }
                Text(subline)
                    .font(Theme.mono(11))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let meta {
                Text(meta)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, 3)
    }

    /// The row's state chips — Installed, Deprecated, Disabled — in the CASK
    /// and UPDATE chips' exact shape, so every fact on the line carries the
    /// same glance weight.
    private func statusPill(
        _ label: String,
        background: Color,
        foreground: Color
    ) -> some View {
        Text(label.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .kerning(0.3)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(foreground)
            .help(label)
            .accessibilityLabel(label)
    }

    /// The design's second line is the version story; the description stands in
    /// when the catalog has no version to tell.
    private var subline: String {
        if let installed = entry.installed {
            if installed.isOutdated {
                return "\(installed.primaryKeg.version)  →  \(installed.catalogVersion)"
            }
            return installed.primaryKeg.version
        }
        if let version = entry.catalog?.version { return version }
        return entry.desc ?? ""
    }

    /// The design's right-hand metric: size on disk where it is a measured
    /// fact, the abbreviated yearly install count where it is not.
    private var meta: String? {
        if let sizeOnDisk, sizeOnDisk > 0 {
            return sizeOnDisk.formatted(.byteCount(style: .file))
        }
        guard let count = entry.catalog?.installCount365d, count > 0 else { return nil }
        return count.formatted(.number.notation(.compactName)) + " / yr"
    }
}

/// Which namespace a row belongs to — drawn only for casks.
///
/// The design chips the exception, not the rule: formulae are the vast
/// majority, so a FORMULA pill on nearly every row is noise, and a row with no
/// chip *is* the formula reading. This revises PS1's "always shown" — the two
/// namespaces stay distinguishable, by the cask pill's presence or absence.
/// The design's update chip: the cask pill's shape in the accent's colours.
///
/// A pill rather than an icon so "this has an update" reads at the same glance
/// weight as the kind — the design chips both facts identically.
struct UpdateTag: View {
    let nextVersion: String
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Text("UPDATE")
            .font(.system(size: 8.5, weight: .bold))
            .kerning(0.3)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(theme.tint(0.2), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(theme.light)
            .help("Update available: \(nextVersion)")
            .accessibilityLabel("Update available: \(nextVersion)")
    }
}

struct KindTag: View {
    let kind: PackageKind

    var body: some View {
        if kind == .cask {
            Text("CASK")
                .font(.system(size: 8.5, weight: .bold))
                .kerning(0.3)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    Theme.caskTint(0.18),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .foregroundStyle(Theme.caskText)
                .accessibilityLabel("Cask")
        }
    }
}

#Preview {
    let package = CatalogPackage(
        kind: .formula, name: "wget", displayName: "wget",
        desc: "Internet file retriever", homepage: nil, license: "GPL-3.0-or-later",
        version: "1.25.0", tap: "homebrew/core", dependencies: [], buildDependencies: [],
        dependents: [], caveats: nil, deprecated: false, deprecationReason: nil,
        deprecationDate: nil, disabled: false, disableReason: nil, disableDate: nil,
        autoUpdates: false, installCount365d: 1_234_567
    )
    return List {
        PackageRow(entry: PackageEntry(installed: nil, catalog: package, id: package.id))
    }
}
