//
//  HomeView.swift
//  cellar
//

import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import Persistence
import SecurityKit
import SwiftUI

/// The landing section, in the design's arrangement: a greeting, the handful of
/// things that want attention, a snapshot strip, and two columns of recent
/// activity and favorites.
///
/// Every number here is a projection over stores the shell already holds —
/// this view refreshes nothing and owns nothing.
struct HomeView: View {
    let brewDetection: BrewDetectionStore
    let catalog: CatalogStore
    let installed: InstalledStore
    let metadata: MetadataStore
    let security: SecurityStore
    let diskUsage: DiskUsageStore
    let taps: TapStore
    let services: ServicesStore
    let history: HistoryStore
    let operations: OperationCenter
    /// The cask artwork pipeline, for the favorites column's cask rows;
    /// `nil` — a preview, say — keeps the letter tile (see `PackageIconTile`).
    var assets: CaskBrowseAssets?
    var iconLoader: CaskIconLoader?
    @Binding var section: AppSection
    @Binding var selection: PackageID?
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(attentionSentence)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.top, 8)

                if brewDetection.state.installation == nil {
                    BrewDetectionSummary(state: brewDetection.state)
                        .padding(.top, 20)
                        .themeCard()
                } else {
                    VStack(spacing: 9) {
                        ForEach(attention) { item in
                            AttentionCard(item: item)
                        }
                    }
                    .padding(.top, 24)

                    snapshotGrid
                        .padding(.top, 26)

                    HStack(alignment: .top, spacing: 24) {
                        recentColumn
                        favoritesColumn
                    }
                    .padding(.top, 30)
                }
            }
            .padding(EdgeInsets(top: 30, leading: 34, bottom: 44, trailing: 34))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.windowBackground)
        .accessibilityIdentifier("home-section")
        // The manifest gate behind the favorites' icon lookups; idempotent, so
        // the Discover pages and this page can all ask (see `CaskBrowseAssets`).
        .task { await assets?.load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(greeting)
                .font(.system(size: 30, weight: .bold))
                .kerning(-0.8)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            Text(machineFacts)
                .font(Theme.mono(12))
                .foregroundStyle(Color.white.opacity(0.36))
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation = switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        let name = NSFullUserName().split(separator: " ").first.map(String.init)
        return name.map { "\(salutation), \($0)" } ?? salutation
    }

    private var machineFacts: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var facts = "macOS \(os.majorVersion).\(os.minorVersion)"
        if let installation = brewDetection.state.installation {
            let version = installation.version
            facts += " · brew \(version.major).\(version.minor).\(version.patch)"
        }
        return facts
    }

    private var attentionSentence: String {
        guard brewDetection.state.installation != nil else {
            return "Cellar is a window onto the brew already on your Mac."
        }
        switch attention.count {
        case 0: return "Everything on this Mac is current."
        case 1: return "One thing wants your attention today. Everything else on this Mac is current."
        default:
            let words = ["Two", "Three", "Four"][min(attention.count - 2, 2)]
            return "\(words) things want your attention today. Everything else on this Mac is current."
        }
    }

    // MARK: - Attention

    private var attention: [AttentionItem] {
        var items: [AttentionItem] = []
        let outdated = installed.inventory.packages.filter(\.isOutdated)
        if !outdated.isEmpty {
            let formulae = outdated.filter { $0.id.kind == .formula }.count
            let casks = outdated.count - formulae
            items.append(
                AttentionItem(
                    id: "updates",
                    title: outdated.count == 1
                        ? "1 package has an update"
                        : "\(outdated.count) packages have updates",
                    sub: [
                        formulae > 0 ? "\(formulae) formula\(formulae == 1 ? "" : "e")" : nil,
                        casks > 0 ? "\(casks) cask\(casks == 1 ? "" : "s")" : nil,
                    ].compactMap(\.self).joined(separator: " · "),
                    systemImage: "arrow.up.circle",
                    tone: .accent(theme),
                    buttonLabel: "Upgrade all",
                    buttonAction: { operations.submit(.upgradeAll) },
                    isButtonEnabled: operations.isAvailable,
                    open: { section = .updates }
                )
            )
        }
        let vulnerable = security.coverages.values.reduce(0) { $0 + $1.vulnerable }
        if vulnerable > 0 {
            items.append(
                AttentionItem(
                    id: "security",
                    title: vulnerable == 1
                        ? "1 advisory affects an installed package"
                        : "\(vulnerable) advisories affect installed packages",
                    sub: "Matched by name and version against OSV.dev",
                    systemImage: "shield",
                    tone: .danger,
                    buttonLabel: "Review",
                    buttonAction: { section = .security },
                    isButtonEnabled: true,
                    open: { section = .security }
                )
            )
        }
        if let cache = diskUsage.visibleSnapshot?.cache, cache.allocatedBytes > 0 {
            items.append(
                AttentionItem(
                    id: "cleanup",
                    title: "\(Self.bytes(cache.allocatedBytes)) of download cache can go",
                    sub: "Re-fetched on demand · installed packages are never touched",
                    systemImage: "cabinet",
                    tone: .neutral,
                    buttonLabel: "Clean up",
                    buttonAction: { section = .cleanup },
                    isButtonEnabled: true,
                    open: { section = .cleanup }
                )
            )
        }
        return items
    }

    // MARK: - Snapshot

    private var snapshotGrid: some View {
        let packages = installed.inventory.packages
        let formulae = packages.filter { $0.id.kind == .formula }.count
        let running = services.services.filter { $0.status == .started }.count
        let tiles: [(value: String, label: String, destination: AppSection)] = [
            (String(packages.count), "Installed", .installed),
            (String(formulae), "Formulae", .installed),
            (String(packages.count - formulae), "Casks", .installed),
            ("\(running) / \(services.services.count)", "Services up", .services),
            (String(taps.inventory.taps.count), "Taps", .taps),
            (diskTotal, "On disk", .cleanup),
        ]
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 6),
            spacing: 9
        ) {
            ForEach(tiles, id: \.label) { tile in
                Button {
                    section = tile.destination
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tile.value)
                            .font(Theme.mono(19, weight: .semibold))
                            .kerning(-0.4)
                            .foregroundStyle(Theme.textPrimary)
                        Text(tile.label)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .themeCard(radius: 10)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var diskTotal: String {
        guard let snapshot = diskUsage.visibleSnapshot else { return "—" }
        let packages = snapshot.packages.reduce(Int64(0)) { $0 + $1.observation.allocatedBytes }
        return Self.bytes(packages + snapshot.cache.allocatedBytes)
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    // MARK: - Recent activity

    private var recentColumn: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Recent activity")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Button("All history") { section = .history }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.base)
            }
            VStack(spacing: 0) {
                let records = Array(history.records.prefix(8))
                if records.isEmpty {
                    Text("Nothing yet — package changes Cellar makes appear here.")
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(Color.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(EdgeInsets(top: 22, leading: 18, bottom: 22, trailing: 18))
                        .background(Theme.rowFill)
                } else {
                    ForEach(records) { record in
                        RecentActivityRow(record: record)
                        if record.id != records.last?.id {
                            HairlineDivider()
                        }
                    }
                }
            }
            .themeCard(fill: Theme.rowFill)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Favorites

    private var favoritesColumn: some View {
        let favorites = installed.inventory.packages
            .filter { metadata.snapshot[$0.id]?.isFavorite == true }
            .sorted { $0.name < $1.name }
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Favorites")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Button("See all") { section = .favorites }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.base)
            }
            VStack(spacing: 0) {
                if favorites.isEmpty {
                    Text("Nothing favorited yet — click the heart on any package to keep it here.")
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(Color.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(EdgeInsets(top: 22, leading: 18, bottom: 22, trailing: 18))
                        .background(Theme.rowFill)
                } else {
                    ForEach(favorites, id: \.id) { package in
                        FavoriteRow(package: package, assets: assets, iconLoader: iconLoader) {
                            selection = package.id
                            section = .installed
                        }
                        if package.id != favorites.last?.id {
                            HairlineDivider()
                        }
                    }
                }
            }
            .themeCard(fill: Theme.rowFill)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Attention card

private struct AttentionItem: Identifiable {
    enum Tone {
        case accent(ThemeStore)
        case danger
        case neutral

        var iconColor: Color {
            switch self {
            case .accent(let theme): theme.base
            case .danger: Theme.dangerBase
            case .neutral: Color.white.opacity(0.55)
            }
        }

        var iconFill: Color {
            switch self {
            case .accent(let theme): theme.tint(0.16)
            case .danger: Theme.dangerTint(0.16)
            case .neutral: Theme.controlFill
            }
        }

        var cardFill: Color {
            switch self {
            case .accent(let theme): theme.tint(0.07)
            case .danger: Theme.dangerTint(0.07)
            case .neutral: Theme.cardFillLoud
            }
        }

        var cardBorder: Color {
            switch self {
            case .accent(let theme): theme.tint(0.22)
            case .danger: Theme.dangerTint(0.22)
            case .neutral: Theme.border
            }
        }

        var buttonFill: Color {
            switch self {
            case .accent(let theme): theme.base
            case .danger: Theme.dangerTint(0.18)
            case .neutral: Color.white.opacity(0.09)
            }
        }

        var buttonText: Color {
            switch self {
            case .accent: Theme.windowBackground
            case .danger: Theme.dangerText
            case .neutral: Theme.textPrimary
            }
        }
    }

    let id: String
    let title: String
    let sub: String
    let systemImage: String
    let tone: Tone
    let buttonLabel: String
    let buttonAction: () -> Void
    let isButtonEnabled: Bool
    let open: () -> Void
}

private struct AttentionCard: View {
    let item: AttentionItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(item.tone.iconColor)
                .frame(width: 32, height: 32)
                .background(item.tone.iconFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(item.sub)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.46))
            }
            Spacer(minLength: 0)
            Button(action: item.buttonAction) {
                Text(item.buttonLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(item.tone.buttonText)
                    .padding(.horizontal, 15)
                    .frame(height: 29)
                    .background(
                        item.tone.buttonFill,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!item.isButtonEnabled)
            .accessibilityIdentifier("home-attention-\(item.id)")
        }
        .padding(EdgeInsets(top: 15, leading: 17, bottom: 15, trailing: 17))
        .themeCard(fill: item.tone.cardFill, stroke: item.tone.cardBorder)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture(perform: item.open)
    }
}

// MARK: - Rows

private struct RecentActivityRow: View {
    let record: HistoryRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 24, height: 24)
                .background(symbolFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(Theme.mono(12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.mono(11))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
            Spacer(minLength: 0)
            Text(record.date, format: .relative(presentation: .named))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.32))
        }
        .padding(EdgeInsets(top: 11, leading: 15, bottom: 11, trailing: 15))
        .background(Theme.rowFill)
    }

    private var detail: String {
        if let versions = record.versions {
            return "\(versions.from) → \(versions.to)"
        }
        return record.verb
    }

    private var symbol: String {
        switch record.verb {
        case "install": "arrow.down"
        case "uninstall", "zap": "trash"
        default: "arrow.up"
        }
    }

    private var symbolColor: Color {
        switch record.verb {
        case "install": Theme.successText
        case "uninstall", "zap": Theme.dangerText
        default: Theme.infoText
        }
    }

    private var symbolFill: Color {
        switch record.verb {
        case "install": Theme.successTint(0.16)
        case "uninstall", "zap": Theme.dangerTint(0.16)
        default: Color(.sRGB, red: 127 / 255, green: 178 / 255, blue: 232 / 255, opacity: 0.16)
        }
    }
}

private struct FavoriteRow: View {
    let package: InstalledPackage
    var assets: CaskBrowseAssets?
    var iconLoader: CaskIconLoader?
    let open: () -> Void
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Button(action: open) {
            HStack(spacing: 11) {
                PackageIconTile(
                    id: package.id,
                    size: 26,
                    fontSize: 12,
                    assets: assets,
                    iconLoader: iconLoader
                )
                Text(package.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(package.primaryKeg.version)
                    .font(Theme.mono(11))
                    .foregroundStyle(Color.white.opacity(0.35))
                Text(status)
                    .font(.system(size: 11))
                    // The design writes the pending update in the accent's
                    // light variant, like every other "this has an update".
                    .foregroundStyle(package.isOutdated ? theme.light : Color.white.opacity(0.35))
                    .frame(width: 96, alignment: .trailing)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .background(Theme.rowFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var status: String {
        package.isOutdated ? "update \(package.catalogVersion)" : "up to date"
    }
}

/// The initial tile the design puts in front of every package, coloured by a
/// stable hash of the name.
struct PackageTile: View {
    let name: String
    var size: CGFloat = 28
    var fontSize: CGFloat = 12
    var cornerRadius: CGFloat = 7

    var body: some View {
        let pair = Theme.tile(for: name)
        Text(name.prefix(1).uppercased())
            .font(Theme.mono(fontSize, weight: .semibold))
            .foregroundStyle(pair.foreground)
            .frame(width: size, height: size)
            .background(
                pair.background,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}
