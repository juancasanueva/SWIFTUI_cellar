import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import SwiftUI

struct CleanupView: View {
    let detection: BrewDetectionStore
    let installed: InstalledStore
    let store: DiskUsageStore

    var body: some View {
        Group {
            if detection.state.installation == nil {
                ContentUnavailableView(
                    "Homebrew is not installed",
                    systemImage: "shippingbox",
                    description: Text("Install Homebrew to measure its storage.")
                )
            } else if store.visiblePackages.isEmpty, !store.isScanning {
                ContentUnavailableView(
                    "No Homebrew storage found",
                    systemImage: "externaldrive",
                    description: Text("Cellar, Caskroom, and cache are empty.")
                )
            } else {
                List {
                    status
                    ForEach(store.visiblePackages) { package in
                        CleanupRow(package: package)
                    }
                    Section("Cache") {
                        LabeledContent("Homebrew cache") {
                            Text(onDisk(store.visibleSnapshot?.cache.allocatedBytes ?? 0))
                        }
                    }
                }
                .accessibilityIdentifier("disk-usage-list")
            }
        }
        .navigationTitle("Cleanup")
        .task(id: detection.state.installation?.executableURL) { await refresh() }
    }

    @ViewBuilder
    private var status: some View {
        if !store.warnings.isEmpty {
            Section {
                Text("Some storage could not be measured")
                    .font(.headline)
                ForEach(store.warnings) { warning in
                    Text("\(warning.area.rawValue.capitalized): \(warning.message)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        if store.isStale {
            Text("Last complete scan — revalidating")
                .foregroundStyle(.secondary)
        }
        if store.isScanning {
            HStack {
                ProgressView(value: progressFraction)
                Button("Cancel") { store.cancel() }
            }
        }
    }

    private var progressFraction: Double {
        guard let progress = store.progress, progress.discoveredUnits > 0 else { return 0 }
        return min(1, Double(progress.completedUnits) / Double(progress.discoveredUnits))
    }

    private func refresh() async {
        guard let installation = detection.state.installation,
              !ProcessInfo.processInfo.arguments.contains("--ui-testing-m3-disk-usage")
        else { return }
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let roots = HomebrewRoots(installation: installation, userCacheDirectory: cacheDirectory)
        await store.loadCached(for: roots.identity)
        let links = Dictionary(
            uniqueKeysWithValues: installed.inventory.packages.map { ($0.id, $0.formulaLinkState) }
        )
        store.startScan(roots: roots, formulaLinks: links)
    }

    private func onDisk(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file)) + " on disk"
    }
}
