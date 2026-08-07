//
//  PackageDetailView.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SwiftUI

/// Everything the catalog knows about one package.
///
/// Absent fields are omitted rather than rendered as empty rows: the projection
/// distinguishes "no license published" from "an empty license string", and this
/// view keeps that distinction visible (package-detail PD1).
struct PackageDetailView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let metadata: MetadataStore
    let id: PackageID?
    @Binding var selection: PackageID?
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        if let id {
            if let package = catalog.package(id) {
                content(for: package)
            } else {
                ContentUnavailableView(
                    "Package details unavailable",
                    systemImage: "shippingbox",
                    description: Text("This installed package is not in Cellar’s core/cask catalog.")
                )
            }
        } else {
            ContentUnavailableView(
                "No package selected",
                systemImage: "shippingbox",
                description: Text("Pick a package from the list.")
            )
        }
    }

    @ViewBuilder
    private func content(for package: CatalogPackage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(for: package)
                actions(for: package)
                PackageMetadataSection(entry: entry(for: package), metadata: metadata)
                statuses(for: package)
                facts(for: package)
                // Renders nothing for a formula, and nothing for a cask that
                // published none of the inspection keys.
                PackageInspectionSection(package: package)
                // The secondary entry point (D4). One explicit button, rendered
                // only when a repository resolves — never on hover, on appear or
                // on selection, and with no `.task` anywhere near it.
                ReleaseNotesSection(
                    package: package,
                    installedVersion: installed.inventory.package(package.id)?.installedVersion
                )
                analytics(for: package)
                dependencies(for: package)
                dependents(for: package)
                caveats(for: package)
            }
            .padding(EdgeInsets(top: 24, leading: 30, bottom: 34, trailing: 30))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.windowBackground)
        .navigationTitle(package.displayName)
    }

    /// The mutation affordances for this package, plus copy-command.
    /// Composed here rather than pulled from the Browse list, so the detail view
    /// shows the installed state this machine actually has — including for a
    /// package the current catalog page never listed.
    private func entry(for package: CatalogPackage) -> PackageEntry {
        PackageEntry(
            installed: installed.inventory.package(package.id),
            catalog: package,
            id: package.id
        )
    }

    @ViewBuilder
    private func actions(for package: CatalogPackage) -> some View {
        HStack(spacing: 10) {
            MutationMenu(center: operations, entry: entry(for: package))
                .menuStyle(.borderlessButton)
                .fixedSize()
            if let target = PackageTarget(package.id) {
                CopyCommandButton(text: MutationCommand.install(target).displayCommand)
            }
            if let guidance = operations.unavailableGuidance {
                Text(guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func header(for package: CatalogPackage) -> some View {
        let installedPackage = installed.inventory.package(package.id)
        HStack(alignment: .top, spacing: 18) {
            PackageTile(name: package.name, size: 62, fontSize: 24, cornerRadius: 15)
            VStack(alignment: .leading, spacing: 7) {
                Text(package.displayName)
                    .font(.system(size: 23, weight: .semibold))
                    .kerning(-0.5)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                HStack(spacing: 9) {
                    Text(versionStory(package: package, installed: installedPackage))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textSecondary)
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 3)
                    Text(package.kind == .formula ? "Formula (CLI)" : "Cask (GUI app)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    statusBadge(package: package, installed: installedPackage)
                }
                if let desc = package.desc {
                    Text(desc)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.top, 2)
                }
            }
            .padding(.top, 3)
            Spacer(minLength: 0)
            favoriteButton(for: package)
                .padding(.top, 6)
        }
    }

    private func versionStory(package: CatalogPackage, installed: InstalledPackage?) -> String {
        guard let installed else { return package.version }
        if installed.isOutdated {
            return "\(installed.primaryKeg.version) → \(installed.catalogVersion)"
        }
        return installed.primaryKeg.version
    }

    @ViewBuilder
    private func statusBadge(package: CatalogPackage, installed: InstalledPackage?) -> some View {
        if let installed {
            if installed.isOutdated {
                PillBadge(label: "Update available", tone: .accent)
            } else {
                PillBadge(label: "Up to date", tone: .success)
            }
        } else {
            PillBadge(label: "Not installed", tone: .neutral)
        }
    }

    /// The design's heart, writing through the same metadata store the list's
    /// star writes — one favorite, two affordances.
    @ViewBuilder
    private func favoriteButton(for package: CatalogPackage) -> some View {
        let isFavorite = metadata.snapshot[package.id]?.isFavorite == true
        Button {
            metadata.setFavorite(!isFavorite, for: package.id)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFavorite ? theme.base : Color.white.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(
                    isFavorite ? theme.tint(0.16) : Theme.controlFill,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!metadata.availability.isAvailable)
        .help(
            metadata.availability.reason
                ?? (isFavorite ? "Remove from favorites" : "Add to favorites")
        )
        .accessibilityLabel(isFavorite ? "Favorite" : "Not a favorite")
        .accessibilityIdentifier("detail-favorite")
    }

    @ViewBuilder
    private func statuses(for package: CatalogPackage) -> some View {
        if package.deprecated || package.disabled {
            VStack(alignment: .leading, spacing: 8) {
                if package.deprecated {
                    StatusNote(
                        badge: .deprecated,
                        reason: package.deprecationReason,
                        date: package.deprecationDate
                    )
                }
                if package.disabled {
                    StatusNote(
                        badge: .disabled,
                        reason: package.disableReason,
                        date: package.disableDate
                    )
                }
            }
        }
    }

    /// The design's three-column fact grid: uppercase micro-labels over plain
    /// values, mono where the value is an identifier.
    @ViewBuilder
    private func facts(for package: CatalogPackage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Details")
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 26, alignment: .topLeading),
                    count: 3
                ),
                alignment: .leading,
                spacing: 16
            ) {
                fact("Version", package.version, mono: true)
                fact("Tap", package.tap, mono: true)
                fact("Type", package.kind == .formula ? "Formula (CLI)" : "Cask (GUI app)")
                if let license = package.license {
                    fact("License", license)
                }
                if let homepage = package.homepage {
                    VStack(alignment: .leading, spacing: 3) {
                        factLabel("Homepage")
                        Link(homepage.absoluteString, destination: homepage)
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.base)
                            .lineLimit(1)
                    }
                }
                if package.kind == .cask, package.autoUpdates {
                    fact("Updates", "Updates itself")
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private func fact(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            factLabel(label)
            Text(value)
                .font(mono ? Theme.mono(12.5) : .system(size: 12.5))
                .foregroundStyle(mono ? Theme.textMono : Color.white.opacity(0.72))
                .textSelection(.enabled)
        }
    }

    private func factLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10.5, weight: .bold))
            .kerning(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.32))
    }

    @ViewBuilder
    private func analytics(for package: CatalogPackage) -> some View {
        Section {
            LabeledContent("Installs", value: package.installCountDescription)
            if let count = package.installCount {
                // The number alone would read as an install total. It is not one.
                Text("\(count.metricDescription), \(count.windowDescription). \(count.lowerBoundNote)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Homebrew published no analytics entry for this package.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader("Analytics")
        }
    }

    @ViewBuilder
    private func dependencies(for package: CatalogPackage) -> some View {
        if !package.dependencies.isEmpty || !package.buildDependencies.isEmpty {
            Section {
                if !package.dependencies.isEmpty {
                    DependencyList(
                        title: "Runtime",
                        entries: package.dependencies,
                        kind: package.kind,
                        selection: $selection
                    )
                }
                if !package.buildDependencies.isEmpty {
                    DependencyList(
                        title: "Build",
                        entries: package.buildDependencies,
                        kind: package.kind,
                        selection: $selection
                    )
                }
            } header: {
                SectionHeader("Direct dependencies")
            }
        }
    }

    @ViewBuilder
    private func dependents(for package: CatalogPackage) -> some View {
        Section {
            if package.dependents.isEmpty {
                Text("Nothing in the catalog depends on this package.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowText(
                    names: package.dependents,
                    kind: package.kind,
                    selection: $selection
                )
            }
        } header: {
            SectionHeader("Required by")
        }
    }

    @ViewBuilder
    private func caveats(for package: CatalogPackage) -> some View {
        if let caveats = package.caveats {
            Section {
                Text(caveats)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                SectionHeader("Caveats")
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.66)
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.34))
            .padding(.top, 4)
    }
}

/// The design's status pill: a dot beside a short word on a tinted capsule.
struct PillBadge: View {
    enum Tone { case accent, success, danger, neutral }

    let label: String
    let tone: Tone
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(text)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .background(fill, in: Capsule())
    }

    private var dot: Color {
        switch tone {
        case .accent: theme.base
        case .success: Theme.successBase
        case .danger: Theme.dangerBase
        case .neutral: Color.white.opacity(0.35)
        }
    }

    private var text: Color {
        switch tone {
        case .accent: theme.light
        case .success: Theme.successText
        case .danger: Theme.dangerText
        case .neutral: Color.white.opacity(0.55)
        }
    }

    private var fill: Color {
        switch tone {
        case .accent: theme.tint(0.16)
        case .success: Theme.successTint(0.15)
        case .danger: Theme.dangerTint(0.15)
        case .neutral: Color.white.opacity(0.07)
        }
    }
}

private struct StatusNote: View {
    let badge: PackageStatusBadge
    let reason: String?
    let date: Date?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: badge.systemImage)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(badge.label)
                    .font(.headline)
                if let reason {
                    Text(reason)
                }
                if let date {
                    Text(date, format: .dateTime.year().month().day())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// One declared dependency list, in the order the payload declared it.
///
/// Never merged with the other list and never deduplicated against it: a package
/// needed both at build time and at run time is two facts, not one
/// (package-detail PD2).
private struct DependencyList: View {
    let title: String
    let entries: [PackageDependency]
    let kind: PackageKind
    @Binding var selection: PackageID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(entries, id: \.name) { entry in
                HStack(spacing: 6) {
                    if let note = entry.resolutionNote {
                        Text(entry.name)
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(entry.name) {
                            selection = PackageID(kind: kind, name: entry.name)
                        }
                        .buttonStyle(.link)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.bottom, 4)
    }
}

private struct FlowText: View {
    let names: [String]
    let kind: PackageKind
    @Binding var selection: PackageID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(names, id: \.self) { name in
                Button(name) {
                    selection = PackageID(kind: kind, name: name)
                }
                .buttonStyle(.link)
            }
        }
    }
}

#Preview {
    @Previewable @State var selection: PackageID?
    return PackageDetailView(
        catalog: CatalogStore(directory: FileManager.default.temporaryDirectory),
        installed: InstalledStore(),
        operations: OperationCenter(),
        metadata: MetadataStore(container: nil),
        id: nil,
        selection: $selection
    )
}
