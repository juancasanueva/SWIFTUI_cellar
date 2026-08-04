import BrewClient
import Catalog
import SwiftUI

struct TapDetailView: View {
    let taps: TapStore
    let installed: InstalledStore
    let operations: OperationCenter
    let tapName: String?
    let currentForceEvidence: @MainActor @Sendable (TapName) -> ForceUntapEvidence?
    let showInInstalled: @MainActor (PackageID) -> Void

    @State private var query = ""
    @State private var kind: PackageKind?

    var body: some View {
        Group {
            if let tap {
                VStack(alignment: .leading, spacing: 0) {
                    header(tap)
                    Divider()
                    filterBar
                    Divider()
                    packageList(for: tap)
                }
            } else {
                ContentUnavailableView(
                    "No tap selected",
                    systemImage: AppSection.taps.systemImage,
                    description: Text("Choose a third-party tap to inspect its packages.")
                )
            }
        }
        .navigationTitle(tap?.name ?? AppSection.taps.title)
    }

    private func header(_ tap: TapRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tap.name)
                .font(.title2.bold())
            if let remote = tap.remote {
                Link(remote.absoluteString, destination: remote)
                    .lineLimit(1)
            }
            if let lastCommit = tap.lastCommit {
                LabeledContent("Last commit", value: lastCommit)
            }
            HStack {
                Button("Untap") { untap(tap) }
                    .disabled(!operations.isAvailable)
                    .accessibilityIdentifier("tap-untap-button")
                if let name = TapName(tap.name), currentForceEvidence(name) != nil {
                    Button("Force Untap", role: .destructive) { requestForceUntap(name) }
                        .disabled(!operations.isAvailable)
                        .accessibilityIdentifier("tap-force-untap-button")
                }
            }
        }
        .padding(16)
    }

    private var filterBar: some View {
        HStack {
            TextField("Filter packages", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("tap-package-filter")
            Picker("Kind", selection: $kind) {
                Text("All").tag(PackageKind?.none)
                Text("Formulae").tag(PackageKind?.some(.formula))
                Text("Casks").tag(PackageKind?.some(.cask))
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
        }
        .padding(12)
    }

    private func packageList(for tap: TapRecord) -> some View {
        List(filteredPackages(for: tap)) { package in
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(package.displayName)
                    Text(package.id.kind == .formula ? "Formula" : "Cask")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let explanation = package.uninstalledExplanation {
                        Text(explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let installedID = package.installedHandoff {
                    Button("Show in Installed") { showInInstalled(installedID) }
                }
            }
        }
        .accessibilityIdentifier("tap-package-list")
    }

    private var tap: TapRecord? {
        guard let tapName else { return nil }
        return taps.inventory.taps.first { $0.name == tapName }
    }

    private func filteredPackages(for tap: TapRecord) -> [TapPackage] {
        TapProjection.filter(
            TapProjection.packages(for: tap, installed: installed.inventory),
            query: query,
            kind: kind
        )
    }

    private func untap(_ tap: TapRecord) {
        guard let command = TapCommand.untap(tap.name) else { return }
        operations.submit(command)
    }

    private func requestForceUntap(_ name: TapName) {
        guard let evidence = currentForceEvidence(name),
              let command = TapCommand.forceUntap(evidence: evidence)
        else { return }
        _ = operations.request(command)
    }
}
