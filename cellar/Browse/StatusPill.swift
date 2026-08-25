//
//  StatusPill.swift
//  cellar
//

import SwiftUI

/// A row's state chip, in the CASK and UPDATE chips' exact shape, so every fact
/// on a package line carries the same glance weight.
///
/// Extracted from `PackageRow`'s own `private func statusPill(…)` because
/// `package-search` PS8 asks the tap search rows to draw the **same** installed
/// mark the catalog rows draw — not one that looks the same. Swift `private` is
/// file-scoped, so "same" was unrepresentable while the pill lived as a method
/// on `PackageRow`; one shared component is what makes it literally true, and
/// what stops the two search surfaces wording one fact two ways
/// (`installed-inventory` II8, `package-trust` PT5).
///
/// `BrowseView.swift` is untouched by the move: the declaration was in
/// `PackageRow.swift` all along.
struct StatusPill: View {
    let label: String
    let background: Color
    let foreground: Color

    /// The installed mark, wherever a surface reports that this Mac already has
    /// the package. The label lives **here** and nowhere else — neither
    /// presenting surface composes it, and neither does any projection.
    static var installed: StatusPill {
        StatusPill(
            label: "Installed",
            background: Theme.successTint(0.16),
            foreground: Theme.successText
        )
    }

    var body: some View {
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
}

#Preview {
    HStack(spacing: 6) {
        StatusPill.installed
        StatusPill(
            label: "Deprecated",
            background: Color.orange.opacity(0.16),
            foreground: Color.orange
        )
    }
    .padding()
}
