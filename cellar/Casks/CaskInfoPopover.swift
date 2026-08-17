//
//  CaskInfoPopover.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The ⓘ affordance every cask card and row shares: a quiet info glyph that
/// opens the record's property table in a popover, CaskHub's own gesture.
/// Owns its presentation state so call sites add one line, not three.
struct CaskInfoButton: View {
    let package: CatalogPackage
    let installed: InstalledStore
    let assets: CaskBrowseAssets

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Cask info")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            CaskInfoPopover(package: package, installed: installed, assets: assets)
        }
        .accessibilityIdentifier("cask-info-\(package.name)")
    }
}

/// The cask record's facts as a Property/Value table — read-only, and drawn
/// entirely from data the app already holds: the vendored catalog record, the
/// browse assets' category map, and the installed inventory. Nothing is
/// fetched to show it.
struct CaskInfoPopover: View {
    let package: CatalogPackage
    let installed: InstalledStore
    let assets: CaskBrowseAssets

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                ForEach(rows, id: \.property) { row in
                    HairlineDivider()
                    tableRow(row)
                }
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
        .frame(width: 560)
        .frame(maxHeight: 520)
        .background(Theme.windowBackground)
        .accessibilityIdentifier("cask-info-popover-\(package.name)")
    }

    // MARK: - Rows

    private struct Row {
        let property: String
        let value: String
        var link: URL? = nil
    }

    /// The table, in CaskHub's own order; a fact the record does not carry is
    /// simply not a row, never an empty one.
    private var rows: [Row] {
        var rows: [Row] = [
            Row(property: "Token", value: package.name),
            Row(property: "Full Token", value: "\(package.tap)/\(package.name)"),
            Row(property: "Tap", value: package.tap),
        ]
        if let homepage = package.homepage {
            rows.append(Row(property: "Homepage", value: homepage.absoluteString, link: homepage))
        }
        if let downloadURL = package.caskInspection?.downloadURL {
            rows.append(Row(property: "URL", value: downloadURL, link: URL(string: downloadURL)))
        }
        if let checksum = package.caskInspection?.declaredChecksum {
            rows.append(Row(property: "SHA", value: checksum.declaredDigest ?? "Not checked"))
        }
        rows.append(Row(property: "Version", value: package.version))
        if let license = package.license {
            rows.append(Row(property: "License", value: license))
        }
        let installedPackage = installed.inventory.package(package.id)
        rows.append(Row(
            property: "Installed Version",
            value: installedPackage?.primaryKeg.version ?? "Not installed"
        ))
        if let category = assets.primaryCategoryName(for: package.name) {
            rows.append(Row(property: "Main Category", value: category))
        }
        rows.append(Row(property: "Auto Updates", value: package.autoUpdates ? "Yes" : "No"))
        if let installedPackage {
            rows.append(Row(property: "Outdated", value: installedPackage.isOutdated ? "Yes" : "No"))
        }
        rows.append(Row(property: "Deprecated", value: package.deprecated ? "Yes" : "No"))
        if let reason = package.deprecationReason {
            rows.append(Row(property: "Deprecation Reason", value: reason))
        }
        rows.append(Row(property: "Disabled", value: package.disabled ? "Yes" : "No"))
        if let reason = package.disableReason {
            rows.append(Row(property: "Disable Reason", value: reason))
        }
        return rows
    }

    // MARK: - Rendering

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Property")
                .frame(width: 150, alignment: .leading)
            Text("Value")
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.textPrimary)
        .padding(.vertical, 8)
    }

    private func tableRow(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(row.property)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 150, alignment: .leading)
            if let link = row.link {
                Link(row.value, destination: link)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(theme.base)
                    .lineLimit(2)
                    .truncationMode(.middle)
            } else {
                Text(row.value)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    @Environment(ThemeStore.self) private var theme
}
