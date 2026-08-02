//
//  InstalledRow.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SwiftUI

/// One installed package.
///
/// Every value here comes from the snapshot; the catalog only contributes the
/// description when the snapshot happened not to carry one. A row for a
/// third-party tap therefore renders in full with no catalog record at all
/// (installed-inventory II7).
struct InstalledRow: View {
    let entry: PackageEntry
    let operations: OperationCenter
    /// Optional so a preview, and a launch whose store would not open, both
    /// render the row in full with the star simply absent.
    var metadata: MetadataStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if metadata != nil { star }
                Text(entry.displayName)
                    .font(.body)
                    .lineLimit(1)
                KindTag(kind: entry.id.kind)
                Text(entry.version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(badges, id: \.self) { badge in
                    badge.view
                }
                Spacer(minLength: 0)
                MutationMenu(center: operations, entry: entry)
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

    /// Reads `PackageMetadata.isFavorite` and writes through the store.
    ///
    /// **Disabled with the reason attached** when the store is unavailable,
    /// rather than hidden or silently inert: an affordance that does nothing
    /// when pressed is the failure mode a degraded store must not produce
    /// (design D4, local-package-metadata LPM6).
    @ViewBuilder
    private var star: some View {
        if let metadata {
            let isFavorite = metadata.snapshot[entry.id]?.isFavorite == true
            Button {
                metadata.setFavorite(!isFavorite, for: entry.id)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!metadata.availability.isAvailable)
            .help(metadata.availability.reason ?? (isFavorite ? "Remove from favorites" : "Add to favorites"))
            .accessibilityLabel(isFavorite ? "Favorite" : "Not a favorite")
        }
    }

    private var badges: [InstalledBadge] {
        guard let installed = entry.installed else { return [] }
        var badges: [InstalledBadge] = []
        // Outdated and "updates itself" are mutually exclusive by construction:
        // `isOutdated` already excludes self-updating casks.
        if installed.isOutdated {
            badges.append(.outdated(installed.catalogVersion))
        }
        if installed.hasNewerVersion {
            badges.append(.selfUpdating(installed.catalogVersion))
        }
        if installed.isPinned {
            badges.append(.pinned(installed.pinnedVersion))
        }
        if !installed.isOnRequest {
            badges.append(.dependency)
        }
        return badges
    }
}

/// A status worth showing next to an installed package.
enum InstalledBadge: Hashable {
    case outdated(String)
    /// Informational only. Never an outdated badge (product decision Q3).
    case selfUpdating(String)
    case pinned(String?)
    case dependency

    var label: String {
        switch self {
        case .outdated(let version): "Update available: \(version)"
        case .selfUpdating(let version): "Updates itself; latest is \(version)"
        case .pinned(let version): version.map { "Pinned at \($0)" } ?? "Pinned"
        case .dependency: "Installed as a dependency"
        }
    }

    var systemImage: String {
        switch self {
        case .outdated: "arrow.up.circle"
        case .selfUpdating: "sparkles"
        case .pinned: "pin"
        case .dependency: "arrow.triangle.branch"
        }
    }

    var tint: Color {
        switch self {
        case .outdated: .orange
        case .selfUpdating, .pinned, .dependency: .secondary
        }
    }

    @ViewBuilder
    var view: some View {
        Label(label, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .foregroundStyle(tint)
            .help(label)
            .accessibilityLabel(label)
    }
}

#Preview {
    let keg = InstalledKeg(
        version: "1.2.3",
        installedAt: Date(timeIntervalSince1970: 1_735_689_600),
        installedOnRequest: true
    )
    let package = InstalledPackage(
        kind: .cask, name: "ghostty", displayName: "Ghostty",
        desc: "Terminal emulator", homepage: nil, tap: "homebrew/cask",
        catalogVersion: "1.3.1", kegs: [keg], primaryKeg: keg,
        snapshotOutdated: false, isPinned: false, pinnedVersion: nil,
        declaresAutoUpdates: true
    )
    return List {
        InstalledRow(
            entry: PackageEntry(installed: package, catalog: nil, id: package.id),
            operations: OperationCenter()
        )
    }
}
