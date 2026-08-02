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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.displayName)
                    .font(.body)
                    .lineLimit(1)
                KindTag(kind: entry.id.kind)
                if entry.isInstalled {
                    Label("Installed", systemImage: "checkmark.circle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .help("Installed")
                        .accessibilityLabel("Installed")
                }
                ForEach(entry.catalog?.badges ?? [], id: \.self) { badge in
                    Label(badge.label, systemImage: badge.systemImage)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .help(badge.label)
                        .accessibilityLabel(badge.label)
                }
                Spacer(minLength: 0)
            }
            if let desc = entry.desc {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Which namespace a row belongs to.
///
/// Always shown, because the same token exists in both and the kind is the only
/// thing distinguishing the two rows (package-search PS1).
struct KindTag: View {
    let kind: PackageKind

    var body: some View {
        Text(kind == .formula ? "formula" : "cask")
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
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
