import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import SwiftUI

struct CleanupView: View {
    let detection: BrewDetectionStore
    let installed: InstalledStore
    let diskUsage: DiskUsageStore
    let cleanup: CleanupStore
    let operations: OperationCenter

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
                cleanupScopes
                storageRows
                packageCleanupScopes
                Section("Cache") {
                    LabeledContent("Homebrew cache") {
                        Text(onDisk(diskUsage.visibleSnapshot?.cache.allocatedBytes ?? 0))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("disk-usage-list")
        }
        .background(Theme.windowBackground)
        .navigationTitle("Cleanup")
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

    @ViewBuilder
    private var cleanupScopes: some View {
        Section("Cleanup previews") {
            scopeControl(.global)
            scopeControl(.full)
            scopeControl(.autoremove)
        }
    }

    @ViewBuilder
    private var storageRows: some View {
        Section("Packages currently on disk") {
            if diskUsage.visiblePackages.isEmpty {
                Text("No Homebrew package storage found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diskUsage.visiblePackages) { package in
                    CleanupRow(package: package)
                }
            }
        }
    }

    @ViewBuilder
    private var packageCleanupScopes: some View {
        if !diskUsage.visiblePackages.isEmpty {
            Section("Package cleanup previews") {
                ForEach(diskUsage.visiblePackages) { package in
                    scopeControl(.package(PackageTarget(package.id)!))
                }
            }
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
            }
        }
    }

    private func scopeControl(_ scope: CleanupScope) -> some View {
        CleanupScopeControl(
            scope: scope,
            state: cleanup.state(for: scope),
            isAvailable: detection.state.installation != nil,
            preview: { preview(scope) },
            cancel: { cleanup.cancelPreview(for: scope) },
            review: { operations.requestCleanup(preview: cleanup.state(for: scope)) }
        )
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

    private func onDisk(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file)) + " on disk"
    }
}

private struct CleanupScopeControl: View {
    let scope: CleanupScope
    let state: CleanupPreviewState
    let isAvailable: Bool
    let preview: () -> Void
    let cancel: () -> Void
    let review: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.title).font(.headline)
                    Text(scope.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !isLoading {
                    Button("Preview", action: preview)
                        .disabled(!isAvailable)
                        .accessibilityLabel("Preview \(scope.title)")
                        .accessibilityHint("Runs Homebrew in dry-run mode without changing files")
                        .accessibilityIdentifier("cleanup-preview-\(scope.key)")
                }
            }
            stateView
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var isLoading: Bool {
        if case .loading = state { true } else { false }
    }

    @ViewBuilder
    private var stateView: some View {
        if !isAvailable {
            stateText("Homebrew is unavailable. Cleanup is read-only until detection recovers.", "unavailable")
        } else {
            switch state {
            case .idle:
                stateText("Preview required before cleanup can be reviewed.", "idle")
            case .loading(let stale):
                stateText(stale == nil ? "Loading cleanup preview…" : "Refreshing stale cleanup preview…", "loading")
                Button("Cancel preview", action: cancel)
                    .accessibilityIdentifier("cleanup-cancel")
            case .content(let result):
                stateText("Preview ready. Review the evidence before continuing.", "content")
                evidence(result)
                Button("Review \(scope.title)", action: review)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Opens a confirmation with the exact command and preview provenance")
                    .accessibilityIdentifier("cleanup-action-\(scope.key)")
            case .empty:
                stateText("Homebrew reported nothing to clean for this scope.", "empty")
            case .partial(let result):
                stateText("The preview is partial or contains unknown Homebrew output. Cleanup is unavailable.", "partial")
                evidence(result)
            case .error(let error, _):
                stateText("The cleanup preview failed. Nothing was changed.", "error")
                Text(error.diagnostics)
                    .font(.caption.monospaced())
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
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("cleanup-state-\(key)")
    }

    @ViewBuilder
    private func evidence(_ result: CleanupPreviewResult) -> some View {
        Text(result.provenanceDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("cleanup-provenance")
        if case .known(let names, let count, let bytes) = result.evidence.orphans {
            Text("\(count) \(count == 1 ? "orphan" : "orphans") reported by Homebrew")
                .accessibilityIdentifier("cleanup-orphan-count")
            ForEach(names, id: \.self) { name in
                Text(name).accessibilityIdentifier("cleanup-orphan-\(name)")
            }
            if let bytes {
                Text("\(bytes.formatted(.byteCount(style: .file))) currently on disk")
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
        case .global: "Homebrew's normal cleanup policy"
        case .full: "All cleanup candidates and cached downloads regardless of age"
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
