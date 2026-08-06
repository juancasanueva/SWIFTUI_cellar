//
//  PackageInspectionSection.swift
//  cellar
//

import Catalog
import SwiftUI

/// One line of the cask inspection section.
///
/// A plain value type rather than formatting inlined into `body`, so what the
/// section *says* about a package is provable without rendering anything. The
/// view below decides layout and nothing else.
///
/// Every fact this needs already exists in CellarCore: the default installation
/// folder is `CaskInstallDestination`, and whether a published download URL may
/// become a link is `CaskInspection.browsableDownloadURL`. Neither is decided
/// here, on purpose — a view is the wrong place to be the thing that decides
/// what is safe to open.
/// `nonisolated` because it is exactly that: a value, with no UI state and no
/// main-actor work. The app target's default isolation is `@MainActor`, and
/// inheriting it here would make the formatting rules only testable from the
/// main actor — which is the wrong reason to be on it.
nonisolated struct PackageInspectionRow: Identifiable, Hashable, Sendable {
    let identifier: String
    let label: String
    let value: String
    /// Extra lines under the value, one per published item.
    var detail: [String] = []
    /// Plain-language context. Never a verdict.
    var note: String?
    /// Non-`nil` only for an `http`/`https` download URL, and only ever supplied
    /// by CellarCore's predicate.
    var link: URL?

    var id: String { identifier }

    /// The rows for one package, in the order the section renders them.
    ///
    /// A row exists only for a value the record actually published. An absent
    /// download URL, checksum, install plan, requirement or conflict list yields
    /// no row at all — the projection distinguishes "not published" from
    /// "published as empty", and rendering an empty row would throw that away.
    static func rows(for package: CatalogPackage) -> [PackageInspectionRow] {
        guard let inspection = package.caskInspection else { return [] }
        var rows: [PackageInspectionRow] = []

        if let downloadURL = inspection.downloadURL {
            rows.append(
                PackageInspectionRow(
                    identifier: "inspection-download",
                    label: "Downloads",
                    value: downloadURL,
                    note: inspection.browsableDownloadURL == nil
                        ? "Shown as text: Cellar opens only web addresses."
                        : nil,
                    link: inspection.browsableDownloadURL
                )
            )
        }

        if let checksum = inspection.declaredChecksum {
            rows.append(
                PackageInspectionRow(
                    identifier: "inspection-checksum",
                    label: "Declared checksum",
                    value: checksum.declaredDigest ?? "This cask declares no checksum",
                    note: "The value this cask declares. Cellar has not downloaded or checked anything."
                )
            )
        }

        if let plan = inspection.installPlan {
            let steps = installSteps(of: plan)
            if !steps.isEmpty {
                rows.append(
                    PackageInspectionRow(
                        identifier: "inspection-installs",
                        label: "Installs",
                        value: steps[0],
                        detail: steps
                    )
                )
            }
            if plan.unrepresentedStanzaCount > 0 {
                rows.append(
                    PackageInspectionRow(
                        identifier: "inspection-remainder",
                        label: "Also",
                        value: remainderPhrase(plan.unrepresentedStanzaCount)
                    )
                )
            }
        }

        if let requirements = inspection.requirements {
            let needs = requirementPhrases(of: requirements)
            if !needs.isEmpty {
                rows.append(
                    PackageInspectionRow(
                        identifier: "inspection-requires",
                        label: "Requires",
                        value: needs[0],
                        detail: needs
                    )
                )
            }
        }

        if let conflicts = inspection.conflicts {
            let clashes = conflicts.casks.map { "The cask \($0)" }
                + conflicts.formulae.map { "The formula \($0)" }
            if !clashes.isEmpty {
                rows.append(
                    PackageInspectionRow(
                        identifier: "inspection-conflicts",
                        label: "Conflicts with",
                        value: clashes[0],
                        detail: clashes
                    )
                )
            }
        }

        return rows
    }

    /// What the cask says it will put on the machine, in plain language.
    ///
    /// Describing a declaration, never announcing an action: nothing here is
    /// something Cellar runs, and the projection carries nothing runnable to
    /// begin with.
    private static func installSteps(of plan: CaskInstallPlan) -> [String] {
        plan.apps.map { app in
            "Installs \(app.source) into \(CaskInstallDestination(appTarget: app.target).path)"
        }
            + plan.binaries.map { binary in
                "Adds the command \(binary.target ?? binary.source)"
            }
            + plan.packageInstallers.map { installer in
                "Runs the installer package \(installer.source)"
            }
    }

    /// The counted remainder, phrased as install steps that are not shown.
    ///
    /// Not "N stanzas": a stanza is a Homebrew implementation word, and the
    /// honest sentence is that Cellar is not showing them — not that they do
    /// nothing, and not that they are safe.
    private static func remainderPhrase(_ count: Int) -> String {
        count == 1
            ? "1 other install step isn’t shown here"
            : "\(count) other install steps aren’t shown here"
    }

    private static func requirementPhrases(of requirements: CaskRequirements) -> [String] {
        (requirements.macOSRequirement.map { ["macOS \($0)"] } ?? [])
            + requirements.formulae.map { "The formula \($0)" }
            + requirements.casks.map { "The cask \($0)" }
    }
}

/// What a cask says it downloads and installs, before you install it.
///
/// Always visible for a cask and never behind a disclosure (D4): the point of
/// the section is to be read *before* an irreversible-feeling action, which a
/// collapsed section is not.
///
/// It makes no claim about signing or origin, because catalog data supports
/// none — the projection it reads has no field that could carry one.
struct PackageInspectionSection: View {
    let package: CatalogPackage

    private var rows: [PackageInspectionRow] { PackageInspectionRow.rows(for: package) }

    var body: some View {
        if !rows.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows) { row in
                        InspectionRowView(row: row)
                    }
                }
            } header: {
                Text("Before you install")
                    .font(.headline)
                    .padding(.top, 4)
            }
        }
    }
}

private struct InspectionRowView: View {
    let row: PackageInspectionRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content
            if let note = row.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier(row.identifier)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if let link = row.link {
            Link(row.value, destination: link)
                .lineLimit(1)
        } else if row.detail.isEmpty {
            Text(row.value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(row.detail, id: \.self) { line in
                    Text(line)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
