//
//  TapSearchSection.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// Packages published by the taps this Mac has installed, below the catalog
/// results.
///
/// The section composes **no copy of its own beyond its title**: the install
/// state and the catalog collision are sentences `TapPackageSearch` supplies, so
/// two surfaces cannot word the same fact differently (package-search PS8).
///
/// It also decides nothing. Which rows may be selected, which carry a collision
/// note and which identity the install names are all facts of the hit, resolved
/// once in the projection and only read here (DD-4).
struct TapSearchSection: View {
    let hits: [TapSearchHit]
    let operations: OperationCenter
    /// The list's current selection, for the design's own row highlight. The
    /// `List` still owns the binding.
    let selection: PackageID?

    var body: some View {
        Section("From your taps") {
            ForEach(hits) { hit in
                if let routable = hit.routableID {
                    row(hit)
                        .tag(routable)
                        .themedListSelection(isSelected: selection == routable)
                } else {
                    // Deliberately inert. Either the catalog carries this token
                    // and would answer for it instead, or nothing on this Mac
                    // has a record to show — so opening a pane would present a
                    // different package than the row chosen, or nothing at all.
                    row(hit)
                        .selectionDisabled()
                }
            }
        }
    }

    private func row(_ hit: TapSearchHit) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(hit.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)
                    KindTag(kind: hit.id.kind)
                    Spacer(minLength: 0)
                }
                Text(hit.tapName)
                    .font(Theme.mono(11))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineLimit(1)
                Text(state(hit))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            // The shared spine, unconditionally: an entry with neither an
            // installed nor a catalog record renders Install and Copy install
            // command, over the bare token (package-mutation PM10).
            MutationMenu(center: operations, entry: entry(for: hit))
        }
        .padding(.vertical, 3)
    }

    /// A row with neither an installed nor a catalog record, identified by the
    /// bare token the projection resolved. `MutationMenu` reads that as "not
    /// installed" and renders exactly Install and Copy install command.
    private func entry(for hit: TapSearchHit) -> PackageEntry {
        PackageEntry(installed: nil, catalog: nil, id: hit.mutationTarget)
    }

    /// The row's sentence — joined from values, never composed from words.
    private func state(_ hit: TapSearchHit) -> String {
        [hit.stateCopy, hit.collisionNote].compactMap(\.self).joined(separator: " ")
    }
}

#Preview {
    List {
        TapSearchSection(hits: [], operations: OperationCenter(), selection: nil)
    }
}
