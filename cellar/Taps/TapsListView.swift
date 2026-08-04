import BrewClient
import SwiftUI

struct TapsListView: View {
    let taps: TapStore
    let operations: OperationCenter
    @Binding var selection: String?

    @State private var target = ""

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
        .onChange(of: taps.inventory) { _, inventory in
            guard let selection,
                  inventory.taps.contains(where: { $0.name == selection })
            else {
                self.selection = nil
                return
            }
        }
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
