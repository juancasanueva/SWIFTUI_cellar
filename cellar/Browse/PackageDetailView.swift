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
            VStack(alignment: .leading, spacing: 20) {
                header(for: package)
                actions(for: package)
                PackageMetadataSection(entry: entry(for: package), metadata: metadata)
                statuses(for: package)
                facts(for: package)
                analytics(for: package)
                dependencies(for: package)
                dependents(for: package)
                caveats(for: package)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(package.displayName)
                    .font(.largeTitle.weight(.semibold))
                KindTag(kind: package.kind)
            }
            if package.displayName != package.name {
                Text(package.name)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let desc = package.desc {
                Text(desc)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
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

    @ViewBuilder
    private func facts(for package: CatalogPackage) -> some View {
        Section {
            LabeledContent("Version", value: package.version)
            LabeledContent("Tap", value: package.tap)
            if let license = package.license {
                LabeledContent("License", value: license)
            }
            if let homepage = package.homepage {
                LabeledContent("Homepage") {
                    Link(homepage.absoluteString, destination: homepage)
                        .lineLimit(1)
                }
            }
            if package.kind == .cask, package.autoUpdates {
                LabeledContent("Updates", value: "Updates itself")
            }
        } header: {
            SectionHeader("Details")
        }
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
            .font(.headline)
            .padding(.top, 4)
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
