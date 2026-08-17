//
//  PackageDetailView.swift
//  cellar
//

import BrewClient
import Catalog
import DiskUsage
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
    /// Read only for the "Size on disk" fact — the same measurement Cleanup
    /// and the Search list show. Nothing here starts a scan.
    let diskUsage: DiskUsageStore
    /// The cask artwork pipeline; `nil` — a preview, say — keeps the letter
    /// tile in the header (see `PackageIconTile`).
    var assets: CaskBrowseAssets?
    var iconLoader: CaskIconLoader?
    let id: PackageID?
    @Binding var selection: PackageID?
    @Environment(ThemeStore.self) private var theme

    /// The design's three tabs. Reset to Overview when the shown package
    /// changes, so a Dependencies view of one package never stands in front of
    /// another.
    private enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case dependencies = "Dependencies"
        case releaseNotes = "Release notes"
    }

    @State private var tab: DetailTab = .overview

    var body: some View {
        if let id {
            if let package = catalog.package(id) {
                content(for: package)
            } else if let snapshot = installed.inventory.package(id) {
                // No catalog record, but the machine has it: the snapshot
                // still carries the identity row, so the package can be
                // favorited without a catalog entry (installed-inventory II7).
                uncatalogedContent(for: snapshot)
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
        VStack(spacing: 0) {
            header(for: package)
                .padding(EdgeInsets(top: 24, leading: 30, bottom: 0, trailing: 30))
            tabStrip
                .padding(.horizontal, 30)
                .padding(.top, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch tab {
                    case .overview:
                        overview(for: package)
                    case .dependencies:
                        dependencies(for: package)
                        dependents(for: package)
                    case .releaseNotes:
                        // The secondary entry point (D4). One explicit button,
                        // rendered only when a repository resolves — never on
                        // hover, on appear or on selection, and with no `.task`
                        // anywhere near it.
                        ReleaseNotesSection(
                            package: package,
                            installedVersion: installed.inventory.package(package.id)?.installedVersion
                        )
                    }
                }
                .padding(EdgeInsets(top: 22, leading: 30, bottom: 34, trailing: 30))
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Theme.windowBackground)
        .navigationTitle(package.displayName)
        .onChange(of: package.id) { _, _ in tab = .overview }
    }

    /// The Overview tab, in the design's order: description, states worth a
    /// banner, the fact grid, cask inspection, analytics, the private note,
    /// caveats, and the actions row last.
    @ViewBuilder
    private func overview(for package: CatalogPackage) -> some View {
        description(for: package)
        statuses(for: package)
        facts(for: package)
        // Renders nothing for a formula, and nothing for a cask that
        // published none of the inspection keys.
        PackageInspectionSection(package: package)
        analytics(for: package)
        PackageMetadataSection(entry: entry(for: package), metadata: metadata)
        caveats(for: package)
        actionsSection(for: package)
    }

    @ViewBuilder
    private func description(for package: CatalogPackage) -> some View {
        if let desc = package.desc {
            VStack(alignment: .leading, spacing: 7) {
                SectionHeader("Description")
                Text(desc)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .frame(maxWidth: 680, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private var tabStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(DetailTab.allCases, id: \.self) { candidate in
                    Button {
                        tab = candidate
                    } label: {
                        Text(candidate.rawValue)
                            .font(.system(size: 12.5, weight: tab == candidate ? .semibold : .medium))
                            .foregroundStyle(
                                tab == candidate ? Theme.textPrimary : Color.white.opacity(0.45)
                            )
                            .padding(.horizontal, 13)
                            .padding(.bottom, 9)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(tab == candidate ? theme.base : .clear)
                                    .frame(height: 2)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("detail-tab-\(candidate.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
                }
                Spacer(minLength: 0)
            }
            HairlineDivider()
        }
    }

    /// The entry the affordances compose over.
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

    /// The design's explicit action row: every verb as a button, the exact
    /// command underneath, danger kept visibly apart. Every submission goes
    /// through `submit(_:)`, so the confirmation rule is applied in exactly one
    /// place — the same discipline `MutationMenu` follows on the list rows.
    @ViewBuilder
    private func actionsSection(for package: CatalogPackage) -> some View {
        if let target = PackageTarget(package.id) {
            let entry = entry(for: package)
            let installedPackage = entry.installed
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Actions")
                HStack(spacing: 8) {
                    if let installedPackage {
                        if installedPackage.isOutdated {
                            quietButton("Upgrade", identifier: "detail-action-upgrade") {
                                submit(.upgrade(target))
                            }
                        }
                        quietButton("Reinstall", identifier: "detail-action-reinstall") {
                            submit(.reinstall(target))
                        }
                        if let formula = FormulaID(package.id) {
                            quietButton(
                                installedPackage.isPinned ? "Unpin" : "Pin version",
                                identifier: "detail-action-pin"
                            ) {
                                submit(installedPackage.isPinned ? .unpin(formula) : .pin(formula))
                            }
                        }
                        snoozeButton(for: entry)
                        dangerButton("Uninstall…", identifier: "detail-action-uninstall") {
                            submit(.uninstall(target))
                        }
                        if let cask = CaskID(package.id) {
                            dangerButton("Uninstall and Zap…", identifier: "detail-action-zap") {
                                submit(.zap(cask))
                            }
                        }
                    } else {
                        accentButton("Install", identifier: "detail-action-install") {
                            submit(.install(target))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .disabled(!operations.isAvailable)
                HStack(spacing: 8) {
                    Text(primaryCommand(for: package, target: target).displayCommand)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textFaint)
                        .textSelection(.enabled)
                    CopyCommandButton(text: primaryCommand(for: package, target: target).displayCommand)
                }
                if let guidance = operations.unavailableGuidance {
                    Text(guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The command the caption shows: what the most likely button would run.
    private func primaryCommand(for package: CatalogPackage, target: PackageTarget) -> MutationCommand {
        guard let installedPackage = installed.inventory.package(package.id) else {
            return .install(target)
        }
        return installedPackage.isOutdated ? .upgrade(target) : .reinstall(target)
    }

    /// Snoozes the currently offered version — the same rule and store the
    /// list rows use, offered only while there is an update to silence (D5).
    @ViewBuilder
    private func snoozeButton(for entry: PackageEntry) -> some View {
        if let installedPackage = entry.installed, installedPackage.isOutdated,
           metadata.availability.isAvailable {
            let offered = installedPackage.catalogVersion
            let isSnoozed = PackageMetadata.isSnoozed(
                offering: offered,
                snoozedVersion: metadata.snapshot[entry.id]?.snoozedVersion
            )
            quietButton(
                isSnoozed ? "Snoozed \(offered)" : "Snooze \(offered)",
                identifier: "detail-action-snooze"
            ) {
                if isSnoozed {
                    metadata.unsnooze(entry.id)
                } else {
                    metadata.snooze(entry.id, offering: offered)
                }
            }
            .help(
                isSnoozed
                    ? "Show the update badge for \(offered) again"
                    : "Hide the badge until a different version is offered"
            )
        }
    }

    /// One entry point for every command, so the confirmation rule is applied
    /// in exactly one place rather than restated per button.
    private func submit(_ command: MutationCommand) {
        if operations.request(command) == nil {
            operations.submit(command)
        }
    }

    // MARK: - Buttons in the design's three tones

    private func quietButton(
        _ label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 13)
                .frame(height: 29)
                .background(
                    Theme.controlFillLoud,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func accentButton(
        _ label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.windowBackground)
                .padding(.horizontal, 14)
                .frame(height: 29)
                .background(theme.base, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func dangerButton(
        _ label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.dangerText)
                .padding(.horizontal, 13)
                .frame(height: 29)
                .background(
                    Theme.dangerTint(0.12),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.dangerTint(0.28), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func header(for package: CatalogPackage) -> some View {
        let installedPackage = installed.inventory.package(package.id)
        header(
            id: package.id,
            displayName: package.displayName,
            versionStory: versionStory(package: package, installed: installedPackage),
            installed: installedPackage
        ) {
            headerPrimaryButton(package: package, installed: installedPackage)
        }
    }

    /// The header alone, for an installed package the catalog does not list.
    /// No tabs and no primary verb — the catalog record those need is exactly
    /// what is absent — but the identity row and the heart still stand.
    @ViewBuilder
    private func uncatalogedContent(for snapshot: InstalledPackage) -> some View {
        VStack(spacing: 0) {
            header(
                id: snapshot.id,
                displayName: snapshot.displayName,
                versionStory: versionStory(installed: snapshot),
                installed: snapshot
            ) {
                EmptyView()
            }
            .padding(EdgeInsets(top: 24, leading: 30, bottom: 0, trailing: 30))
            ContentUnavailableView(
                "No further details",
                systemImage: "shippingbox",
                description: Text("This installed package is not in Cellar’s core/cask catalog.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.windowBackground)
        .navigationTitle(snapshot.displayName)
    }

    /// The one identity row both paths render: tile, name, version story, kind,
    /// status and the heart — fed by the catalog record when there is one and
    /// by the snapshot alone when there is not.
    @ViewBuilder
    private func header(
        id: PackageID,
        displayName: String,
        versionStory: String,
        installed installedPackage: InstalledPackage?,
        @ViewBuilder primaryButton: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 18) {
            PackageIconTile(
                id: id,
                size: 62,
                fontSize: 24,
                cornerRadius: 15,
                assets: assets,
                iconLoader: iconLoader
            )
            VStack(alignment: .leading, spacing: 7) {
                Text(displayName)
                    .font(.system(size: 23, weight: .semibold))
                    .kerning(-0.5)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                HStack(spacing: 9) {
                    Text(versionStory)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textSecondary)
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 3)
                    Text(id.kind == .formula ? "Formula (CLI)" : "Cask (GUI app)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    statusBadge(installed: installedPackage)
                }
            }
            .padding(.top, 3)
            Spacer(minLength: 0)
            primaryButton()
                .padding(.top, 6)
            favoriteButton(for: id)
                .padding(.top, 6)
        }
    }

    /// The header's one accent action, shown only when it offers something the
    /// package does not already have: Install when absent, Upgrade when
    /// outdated. An up-to-date package keeps its verbs in the Actions row.
    @ViewBuilder
    private func headerPrimaryButton(package: CatalogPackage, installed: InstalledPackage?) -> some View {
        if let target = PackageTarget(package.id) {
            if installed == nil {
                accentButton("Install", identifier: "detail-primary-install") {
                    submit(.install(target))
                }
                .disabled(!operations.isAvailable)
            } else if installed?.isOutdated == true {
                accentButton("Upgrade", identifier: "detail-primary-upgrade") {
                    submit(.upgrade(target))
                }
                .disabled(!operations.isAvailable)
            }
        }
    }

    private func versionStory(package: CatalogPackage, installed: InstalledPackage?) -> String {
        guard let installed else { return package.version }
        return versionStory(installed: installed)
    }

    private func versionStory(installed: InstalledPackage) -> String {
        if installed.isOutdated {
            return "\(installed.primaryKeg.version) → \(installed.catalogVersion)"
        }
        return installed.primaryKeg.version
    }

    @ViewBuilder
    private func statusBadge(installed: InstalledPackage?) -> some View {
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

    /// The design's heart, writing through the same metadata store the
    /// Favorites list's heart writes — one favorite, two affordances.
    @ViewBuilder
    private func favoriteButton(for id: PackageID) -> some View {
        let isFavorite = metadata.snapshot[id]?.isFavorite == true
        Button {
            metadata.setFavorite(!isFavorite, for: id)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFavorite ? Color.red : Color.white.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(
                    isFavorite ? Color.red.opacity(0.16) : Theme.controlFill,
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
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 26, alignment: .topLeading),
                    count: 3
                ),
                alignment: .leading,
                spacing: 16
            ) {
                fact("Version", package.version, mono: true)
                if let size = sizeOnDisk(for: package.id) {
                    fact("Size on disk", size.formatted(.byteCount(style: .file)), mono: true)
                }
                if let installedAs = installedAs(for: package.id) {
                    fact("Installed as", installedAs)
                }
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

    /// The measured size, when this machine has the package and the disk scan
    /// has answered — the settled snapshot first, then the in-flight scan's
    /// incremental answer.
    private func sizeOnDisk(for id: PackageID) -> Int64? {
        if let usage = diskUsage.incrementalPackages[id] {
            return usage.observation.allocatedBytes
        }
        return diskUsage.visiblePackages
            .first { $0.id == id }?
            .observation.allocatedBytes
    }

    /// The design's "Installed as" fact — only for installed packages, where
    /// it is a recorded fact of the keg rather than a guess.
    private func installedAs(for id: PackageID) -> String? {
        guard let installedPackage = installed.inventory.package(id) else { return nil }
        return installedPackage.isOnRequest ? "Installed on request" : "Installed as a dependency"
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

    /// The design's "Requires" card: one bordered well, a square dot per row —
    /// green for runtime, quiet for build — the name in mono, the kind as a
    /// tag. Runtime and build stay separate entries even for the same name:
    /// two facts, never merged (package-detail PD2).
    @ViewBuilder
    private func dependencies(for package: CatalogPackage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Requires")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if package.dependencies.isEmpty && package.buildDependencies.isEmpty {
                Text("This package declares no direct dependencies.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(package.dependencies, id: \.name) { dependency in
                        requiresRow(dependency, tag: "runtime", dot: Theme.successText, kind: package.kind)
                    }
                    ForEach(package.buildDependencies, id: \.name) { dependency in
                        requiresRow(dependency, tag: "build", dot: Color.white.opacity(0.3), kind: package.kind)
                    }
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                .frame(maxWidth: 820, alignment: .leading)
                .themeCard(fill: Color.white.opacity(0.02), radius: 10)
            }
        }
    }

    private func requiresRow(
        _ dependency: PackageDependency,
        tag: String,
        dot: Color,
        kind: PackageKind
    ) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1)
                .fill(dot)
                .frame(width: 5, height: 5)
            if let note = dependency.resolutionNote {
                Text(dependency.name)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(Theme.textMono)
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.34))
            } else {
                Button {
                    selection = PackageID(kind: kind, name: dependency.name)
                } label: {
                    Text(dependency.name)
                        .font(Theme.mono(12.5))
                        .foregroundStyle(Theme.textMono)
                }
                .buttonStyle(.plain)
                Text(tag)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.34))
            }
            Spacer(minLength: 0)
        }
    }

    /// The design's "Required by" rows: one accent-tinted pill per dependent,
    /// the name in the accent's light tone, still a jump to that package.
    @ViewBuilder
    private func dependents(for package: CatalogPackage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Required by")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if package.dependents.isEmpty {
                Text("Nothing in the catalog depends on this package.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(package.dependents, id: \.self) { name in
                        Button {
                            selection = PackageID(kind: package.kind, name: name)
                        } label: {
                            HStack(spacing: 9) {
                                Circle().fill(theme.base).frame(width: 5, height: 5)
                                Text(name)
                                    .font(Theme.mono(12.5))
                                    .foregroundStyle(theme.light)
                                Spacer(minLength: 0)
                            }
                            .padding(EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13))
                            .themeCard(fill: theme.tint(0.1), stroke: theme.tint(0.2), radius: 8)
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
            }
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

#Preview {
    @Previewable @State var selection: PackageID?
    return PackageDetailView(
        catalog: CatalogStore(directory: FileManager.default.temporaryDirectory),
        installed: InstalledStore(),
        operations: OperationCenter(),
        metadata: MetadataStore(container: nil),
        diskUsage: DiskUsageStore(
            cache: DiskUsageCache(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("preview-detail-disk-usage.json")
            )
        ),
        id: nil,
        selection: $selection
    )
}
