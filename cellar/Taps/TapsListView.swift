import BrewClient
import BrewProcess
import Catalog
import SwiftUI

struct TapsListView: View {
    let taps: TapStore
    let operations: OperationCenter
    /// Read only to project the Brewfile diff, out of the snapshot the app is
    /// already holding. Nothing here forces a refresh (`brewfile-management` BF6).
    let installed: InstalledStore
    let detection: BrewDetectionState
    @Binding var selection: String?

    /// The dump seam, injectable so a test never spawns. The default is the
    /// shipped source, so the ordinary app path is the one being tested.
    var dumpSource: any BundleDumpSourcing = BundleDumpSource()
    /// The AppKit seam an import reads through (design DD4).
    var sourceChooser: any BrewfileSourceChoosing = BrewfileSourcePanel()

    @State private var target = ""
    /// Both Brewfile surfaces read this one store. Owned here rather than in the
    /// composition root because it has no cadence, no cache and no loop: its only
    /// caller is one of the two toolbar buttons below.
    @State private var brewfile = BrewfileStore()
    @State private var isImportPresented = false
    @State private var isExportPresented = false

    var body: some View {
        VStack(spacing: 0) {
            addBar
            Divider()
            List(selection: $selection) {
                Section("Official sources") {
                    ForEach(projection.officialSources) { source in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.title)
                            Text(source.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier(
                                    "official-tap-explanation-"
                                        + source.id.replacingOccurrences(of: "/", with: "-")
                                )
                        }
                    }
                }

                Section("Third-party taps") {
                    ForEach(projection.thirdPartyTaps) { tap in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tap.name)
                            Text(packageCount(for: tap))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(tap.name)
                    }

                    if case .content(isThirdPartyEmpty: true) = presentationState {
                        Text("No third-party taps are installed.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay { blockingState }
            .accessibilityIdentifier("taps-list")
        }
        .navigationTitle(AppSection.taps.title)
        // Inside the section the user is already in, as two actions rather than
        // a tenth sidebar place (D3). No new `AppSection` case, and no
        // navigation destination.
        .toolbar {
            // Static labels, deliberately. `TapShippingProofTests` enumerates
            // every button label this surface can present, and fails on a
            // trailing-closure button form whose label it cannot read — the tap
            // action surface stays bounded by enumeration, and these two join
            // the enumeration rather than escaping it.
            ToolbarItem {
                Button("Import Brewfile", systemImage: "square.and.arrow.down") {
                    Task { await beginImport() }
                }
                .help("Read a Brewfile and choose what to install")
                .disabled(operations.isAvailable == false)
                .accessibilityIdentifier("brewfile-import-affordance")
            }
            ToolbarItem {
                Button("Export Brewfile", systemImage: "square.and.arrow.up") {
                    isExportPresented = true
                }
                .help("Write a Brewfile describing what this Mac has installed")
                .disabled(detection.installation == nil)
                .accessibilityIdentifier("brewfile-export-affordance")
            }
        }
        .sheet(isPresented: $isImportPresented) {
            BrewfileImportSheet(store: brewfile, operations: operations)
        }
        .sheet(isPresented: $isExportPresented) {
            BrewfileExportSheet(store: brewfile, source: dumpSource, detection: detection)
        }
        .onChange(of: taps.inventory) { _, inventory in
            guard let selection,
                  inventory.taps.contains(where: { $0.name == selection })
            else {
                self.selection = nil
                return
            }
        }
    }

    /// The panel first, then the sheet.
    ///
    /// Opening the sheet first would show an empty diff behind a modal panel and
    /// leave a "no file chosen" sheet standing if the user cancelled. Cancelling
    /// here presents nothing at all, which is what makes cancelling an ordinary
    /// answer rather than a failure.
    private func beginImport() async {
        await brewfile.importFile(
            from: sourceChooser,
            installed: installed.inventory,
            taps: taps.inventory
        )
        guard brewfile.diff != nil || brewfile.importState != .idle else { return }
        isImportPresented = true
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                TextField("user/repo", text: $target)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("tap-add-field")
                    .onSubmit(addTap)
                Button("Add Tap", action: addTap)
                    .disabled(addCommand == nil || !projection.canAddTap || !operations.isAvailable)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityIdentifier("tap-add-button")
            }
            if !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               addCommand == nil {
                Text("Enter a tap as user/repo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var blockingState: some View {
        switch presentationState {
        case .idle, .loading(hasLastGood: false):
            ProgressView("Loading taps")
        case .unavailable(let absence):
            ContentUnavailableView(
                absence.title,
                systemImage: "externaldrive.badge.questionmark",
                description: Text(absence.explanation)
            )
        case .error(let error, hasLastGood: false):
            ContentUnavailableView(
                "Could not load taps",
                systemImage: "exclamationmark.triangle",
                description: Text(error.description)
            )
        case .loading(hasLastGood: true), .content, .error(_, hasLastGood: true):
            EmptyView()
        }
    }

    private var projection: TapProjection {
        TapProjection(inventory: taps.inventory, isAvailable: taps.absence == nil)
    }

    private var presentationState: TapPresentationState {
        TapProjection.state(loadState: taps.state, inventory: taps.inventory)
    }

    private var addCommand: TapCommand? {
        TapCommand.add(target.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func addTap() {
        guard let command = addCommand else { return }
        _ = operations.request(command)
    }

    private func packageCount(for tap: TapRecord) -> String {
        let count = tap.formulaNames.count + tap.caskTokens.count
        return "\(count) package\(count == 1 ? "" : "s")"
    }
}

private extension TapInventoryError {
    var description: String {
        switch self {
        case .brewUnavailable: "Homebrew is not available."
        case .commandFailed(let status, let message):
            message.isEmpty ? "brew exited with status \(status)." : message
        case .blankOutput: "brew returned no tap information."
        case .malformedJSON, .nonArrayEnvelope: "brew returned tap information Cellar could not read."
        case .cancelled: "The refresh was cancelled."
        }
    }
}
