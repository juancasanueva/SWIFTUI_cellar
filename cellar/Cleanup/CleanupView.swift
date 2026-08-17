import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import SwiftUI

/// Storage and reclamation, preview-first.
///
/// The page leads with what Homebrew is using (the stacked bar), then what a
/// cleanup could reclaim (the three scopes, each one honest brew command), and
/// only then the per-package inventory. Nothing spawns brew until a Preview is
/// clicked, and nothing is removed without a confirmed review — the CO7
/// discipline the state machine below renders.
struct CleanupView: View {
    let detection: BrewDetectionStore
    let installed: InstalledStore
    let diskUsage: DiskUsageStore
    let cleanup: CleanupStore
    let operations: OperationCenter

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Cleanup")
                    .font(.system(size: 27, weight: .semibold))
                    .kerning(-0.6)
                    .foregroundStyle(Theme.textPrimary)
                Text(headline)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.white.opacity(0.48))
            }
            .padding(EdgeInsets(top: 28, leading: 34, bottom: 18, trailing: 34))
            List {
                storageStatus
                usageBarSection
                reclaimableSection
                storageRows
            }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("disk-usage-list")
        }
        .background(Theme.windowBackground)
        .task(id: detection.state.installation?.executableURL) { await refreshStorage() }
    }

    /// The design's one-sentence summary: how much Homebrew is using, and how
    /// much of it is cache that can go.
    private var headline: String {
        let packages = diskUsage.visibleSnapshot?.packages
            .reduce(Int64(0)) { $0 + $1.observation.allocatedBytes } ?? 0
        let cache = diskUsage.visibleSnapshot?.cache.allocatedBytes ?? 0
        guard packages + cache > 0 else {
            return "Preview what Homebrew could clean before anything runs."
        }
        var sentence = "Homebrew is using \((packages + cache).formatted(.byteCount(style: .file)))."
        if cache > 0 {
            sentence += " \(cache.formatted(.byteCount(style: .file))) of that is cache"
                + " that can go without touching anything you installed."
        }
        return sentence
    }

    // MARK: - The usage bar

    private struct UsageSegment: Identifiable {
        let name: String
        let bytes: Int64
        let color: Color

        var id: String { name }
    }

    /// Where the bytes live, from the same snapshot the rows render. Unlinked
    /// kegs split out of the Cellar segment because "on disk but not linked"
    /// is worth seeing — labelled with keg-only in mind, since formulae brew
    /// deliberately never links are the segment's ordinary residents, not a
    /// problem to fix.
    private var segments: [UsageSegment] {
        let packages = diskUsage.visiblePackages
        let formulaVersions = packages
            .filter { $0.id.kind == .formula }
            .flatMap(\.versions)
        let cellar = formulaVersions
            .filter { $0.linkState != .unlinked }
            .reduce(Int64(0)) { $0 + $1.observation.allocatedBytes }
        let unlinked = formulaVersions
            .filter { $0.linkState == .unlinked }
            .reduce(Int64(0)) { $0 + $1.observation.allocatedBytes }
        let caskroom = packages
            .filter { $0.id.kind == .cask }
            .reduce(Int64(0)) { $0 + $1.observation.allocatedBytes }
        let cache = diskUsage.visibleSnapshot?.cache.allocatedBytes ?? 0
        return [
            UsageSegment(name: "Cellar", bytes: cellar, color: theme.base),
            UsageSegment(name: "Download cache", bytes: cache, color: Color.blue.opacity(0.8)),
            UsageSegment(name: "Caskroom", bytes: caskroom, color: Color.purple.opacity(0.8)),
            UsageSegment(name: "Keg-only & unlinked", bytes: unlinked, color: Color.white.opacity(0.35)),
        ].filter { $0.bytes > 0 }
    }

    @ViewBuilder
    private var usageBarSection: some View {
        let segments = segments
        let total = segments.reduce(Int64(0)) { $0 + $1.bytes }
        if total > 0 {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geometry in
                        HStack(spacing: 2) {
                            ForEach(segments) { segment in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(segment.color)
                                    .frame(
                                        width: max(
                                            4,
                                            geometry.size.width
                                                * CGFloat(segment.bytes) / CGFloat(total)
                                        )
                                    )
                            }
                        }
                    }
                    .frame(height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    // The combined element is the bar alone, so the rescan
                    // control below stays its own, reachable element.
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        segments.map {
                            "\($0.name) \($0.bytes.formatted(.byteCount(style: .file)))"
                        }.joined(separator: ", ")
                    )
                    HStack(spacing: 16) {
                        ForEach(segments) { segment in
                            HStack(spacing: 6) {
                                Circle().fill(segment.color).frame(width: 7, height: 7)
                                Text(segment.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                Text(segment.bytes.formatted(.byteCount(style: .file)))
                                    .font(Theme.mono(10.5))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer(minLength: 0)
                        // A scan runs on entry and after a confirmed cleanup —
                        // this is for the change those never see, like a
                        // `brew cleanup` run from a terminal while this page
                        // is open. Absent mid-scan: Cancel owns that state.
                        if !diskUsage.isScanning {
                            Button("Rescan storage") { Task { await refreshStorage() } }
                                .buttonStyle(ActionPillStyle())
                                .disabled(detection.state.installation == nil)
                                .help("Measure Homebrew's storage again")
                                .accessibilityIdentifier("cleanup-rescan")
                        }
                    }
                }
                .padding(.vertical, 6)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Reclaimable

    private var reclaimableSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Reclaimable")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("brew cleanup --prune=all -n")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 8)
                    Button("Preview all") {
                        preview(.global)
                        preview(.full)
                        preview(.autoremove)
                    }
                    .buttonStyle(ActionPillStyle())
                    .disabled(detection.state.installation == nil)
                    .help("Runs the three dry-runs below. Nothing is removed.")
                    .accessibilityIdentifier("cleanup-preview-all")
                }
                VStack(alignment: .leading, spacing: 0) {
                    scopeRow(.global)
                    HairlineDivider()
                    scopeRow(.full)
                    HairlineDivider()
                    scopeRow(.autoremove)
                }
                .themeCard(radius: 10)
                Text(
                    """
                    Every action shows the exact command and Homebrew's own dry-run \
                    evidence before anything runs. Nothing is removed without a \
                    confirmed review.
                    """
                )
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .foregroundStyle(Color.white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private func scopeRow(_ scope: CleanupScope) -> some View {
        CleanupScopeRow(
            scope: scope,
            state: cleanup.state(for: scope),
            isAvailable: detection.state.installation != nil,
            preview: { preview(scope) },
            cancel: { cleanup.cancelPreview(for: scope) },
            review: { operations.requestCleanup(preview: cleanup.state(for: scope)) }
        )
    }

    // MARK: - Storage

    @ViewBuilder
    private var storageRows: some View {
        Section("Packages currently on disk") {
            if diskUsage.visiblePackages.isEmpty {
                Text("No Homebrew package storage found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diskUsage.visiblePackages) { package in
                    storageRow(package)
                }
            }
        }
    }

    /// One package: the disclosure row it always had, with that package's own
    /// preview-first cleanup in its label — the merge that retired the second,
    /// noise-only "Package cleanup previews" list. The pills ride inside the
    /// label because the disclosure must stay the row's top-level view.
    @ViewBuilder
    private func storageRow(_ package: DiskPackageUsage) -> some View {
        if let target = PackageTarget(package.id) {
            let scope = CleanupScope.package(target)
            CleanupRow(
                package: package,
                accessory: AnyView(
                    CleanupScopePills(
                        scope: scope,
                        state: cleanup.state(for: scope),
                        isAvailable: detection.state.installation != nil,
                        preview: { preview(scope) },
                        cancel: { cleanup.cancelPreview(for: scope) },
                        review: { operations.requestCleanup(preview: cleanup.state(for: scope)) }
                    )
                ),
                detailHeader: AnyView(
                    CleanupStateLines(state: cleanup.state(for: scope), isAvailable: true)
                )
            )
        } else {
            CleanupRow(package: package)
        }
    }

    @ViewBuilder
    private var storageStatus: some View {
        if detection.state.installation == nil {
            Section {
                Label("Homebrew is not installed", systemImage: "shippingbox")
                    .font(.headline)
                Text("Install Homebrew or check its configured location to preview cleanup.")
                    .foregroundStyle(.secondary)
            }
        }
        if !diskUsage.warnings.isEmpty {
            Section {
                Text("Some storage could not be measured")
                    .font(.headline)
                ForEach(diskUsage.warnings) { warning in
                    Text("\(warning.area.rawValue.capitalized): \(warning.message)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        if diskUsage.isStale {
            Text("Last complete scan — revalidating")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cleanup-post-terminal-refresh")
        }
        if diskUsage.isScanning {
            HStack {
                ProgressView(value: progressFraction)
                Button("Cancel storage scan") { diskUsage.cancel() }
                    .buttonStyle(ActionPillStyle())
            }
        }
    }

    private var progressFraction: Double {
        guard let progress = diskUsage.progress, progress.discoveredUnits > 0 else { return 0 }
        return min(1, Double(progress.completedUnits) / Double(progress.discoveredUnits))
    }

    private func preview(_ scope: CleanupScope) {
        cleanup.startPreview(
            scope: scope,
            for: detection.state,
            diskUsage: diskUsage.visibleSnapshot.map {
                CleanupDiskUsageContext(snapshot: $0, expectedRoots: $0.roots)
            }
        )
    }

    private func refreshStorage() async {
        guard let installation = detection.state.installation,
              !AppTestFixtures.isEnabled
        else { return }
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let roots = HomebrewRoots(installation: installation, userCacheDirectory: cacheDirectory)
        await diskUsage.loadCached(for: roots.identity)
        let links = Dictionary(
            uniqueKeysWithValues: installed.inventory.packages.map { ($0.id, $0.formulaLinkState) }
        )
        diskUsage.startScan(roots: roots, formulaLinks: links)
    }
}

// MARK: - The scope card row

/// One reclaimable scope, in the design's card row shape: title and summary on
/// the left, the reported size and the controls on the right, the state's own
/// sentences beneath.
private struct CleanupScopeRow: View {
    let scope: CleanupScope
    let state: CleanupPreviewState
    let isAvailable: Bool
    let preview: () -> Void
    let cancel: () -> Void
    let review: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(scope.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(scope.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.45))
                CleanupStateLines(state: state, isAvailable: isAvailable)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                if let bytes = reclaimableBytes {
                    Text(bytes.formatted(.byteCount(style: .file)))
                        .font(Theme.mono(12.5))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                CleanupScopePills(
                    scope: scope,
                    state: state,
                    isAvailable: isAvailable,
                    preview: preview,
                    cancel: cancel,
                    review: review
                )
            }
        }
        .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
        .accessibilityElement(children: .contain)
    }

    /// Homebrew's own footer total, when the preview carried one — never a
    /// substituted row-size sum.
    private var reclaimableBytes: Int64? {
        switch state {
        case .content(let result), .partial(let result), .stale(let result):
            if case .reportedFooter(let bytes) = result.evidence.total { return bytes }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - The pills

/// Preview / Cancel / Review, driven by the same state machine everywhere: a
/// preview may be cancelled while loading, and Review exists only over a
/// complete preview (CO7).
private struct CleanupScopePills: View {
    let scope: CleanupScope
    let state: CleanupPreviewState
    let isAvailable: Bool
    let preview: () -> Void
    let cancel: () -> Void
    let review: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                Button("Cancel", action: cancel)
                    .buttonStyle(ActionPillStyle())
                    .accessibilityIdentifier("cleanup-cancel")
            } else {
                Button("Preview", action: preview)
                    .buttonStyle(ActionPillStyle())
                    .disabled(!isAvailable)
                    .accessibilityLabel("Preview \(scope.title)")
                    .accessibilityHint("Runs Homebrew in dry-run mode without changing files")
                    .accessibilityIdentifier("cleanup-preview-\(scope.key)")
                if case .content = state {
                    Button("Review…", action: review)
                        .buttonStyle(ActionPillStyle())
                        .accessibilityLabel("Review \(scope.title)")
                        .accessibilityHint(
                            "Opens a confirmation with the exact command and preview provenance"
                        )
                        .accessibilityIdentifier("cleanup-action-\(scope.key)")
                }
            }
        }
    }

    private var isLoading: Bool {
        if case .loading = state { true } else { false }
    }
}

// MARK: - The state's sentences

/// What the preview state has to say, without buttons: every sentence and
/// identifier the CO7 matrix asserts, minus idle — the Preview pill already
/// says what idle needed a sentence for.
private struct CleanupStateLines: View {
    let state: CleanupPreviewState
    let isAvailable: Bool

    var body: some View {
        if !isAvailable {
            stateText("Homebrew is unavailable. Cleanup is read-only until detection recovers.", "unavailable")
        } else {
            switch state {
            case .idle:
                EmptyView()
            case .loading(let stale):
                stateText(stale == nil ? "Loading cleanup preview…" : "Refreshing stale cleanup preview…", "loading")
            case .content(let result):
                stateText("Preview ready. Review the evidence before continuing.", "content")
                evidence(result)
            case .empty:
                stateText("Homebrew reported nothing to clean for this scope.", "empty")
            case .partial(let result):
                stateText("The preview is partial or contains unknown Homebrew output. Cleanup is unavailable.", "partial")
                evidence(result)
            case .error(let error, _):
                stateText("The cleanup preview failed. Nothing was changed.", "error")
                Text(error.diagnostics)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("cleanup-diagnostics")
            case .cancelled:
                stateText("The cleanup preview was cancelled. Nothing was changed.", "cancelled")
            case .stale(let result):
                stateText("The preview changed or is stale. Preview again before reconfirming.", "stale")
                evidence(result)
            }
        }
    }

    private func stateText(_ value: String, _ key: String) -> some View {
        Text(value)
            .font(.system(size: 11.5))
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.top, 2)
            .accessibilityIdentifier("cleanup-state-\(key)")
    }

    @ViewBuilder
    private func evidence(_ result: CleanupPreviewResult) -> some View {
        Text(result.provenanceDescription)
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.4))
            .accessibilityIdentifier("cleanup-provenance")
        if case .known(let names, let count, let bytes) = result.evidence.orphans {
            Text("\(count) \(count == 1 ? "orphan" : "orphans") reported by Homebrew")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.4))
                .accessibilityIdentifier("cleanup-orphan-count")
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .accessibilityIdentifier("cleanup-orphan-\(name)")
            }
            if let bytes {
                Text("\(bytes.formatted(.byteCount(style: .file))) currently on disk")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .accessibilityIdentifier("cleanup-orphan-allocation")
            }
        }
    }
}

private extension CleanupScope {
    var key: String {
        switch self {
        case .global: "global"
        case .full: "full"
        case .autoremove: "autoremove"
        case .package(let target): "package-\(target.kind.rawValue)-\(target.name)"
        }
    }

    var title: String {
        switch self {
        case .global: "Cleanup"
        case .full: "Full cleanup"
        case .autoremove: "Autoremove"
        case .package(let target): "Clean \(target.name)"
        }
    }

    var summary: String {
        switch self {
        case .global: "Old versions and cache past Homebrew's age policy"
        case .full: "All cleanup candidates and cached downloads regardless of age — this is what clears the download cache"
        case .autoremove: "Formulae no longer required as dependencies"
        case .package: "Cleanup limited to this package"
        }
    }
}

private extension CleanupPreviewResult {
    var provenanceDescription: String {
        switch evidence.total {
        case .reportedFooter(let bytes):
            "Homebrew reported \(bytes.formatted(.byteCount(style: .file))) reclaimable in its preview footer."
        case .unknown:
            "Homebrew did not report a reclaimable total. Row sizes are not substituted."
        }
    }
}

private extension CleanupPreviewError {
    var diagnostics: String {
        switch self {
        case .unavailable(let reason): String(describing: reason)
        case .commandFailed(_, let stdout, let stderr), .cancelled(let stdout, let stderr):
            String(data: stderr.isEmpty ? stdout : stderr, encoding: .utf8) ?? "Unreadable Homebrew diagnostics"
        case .launchFailed(let error): String(describing: error)
        }
    }
}
