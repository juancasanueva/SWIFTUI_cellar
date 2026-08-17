import BrewClient
import Catalog
import SwiftUI

struct TapsListView: View {
    let taps: TapStore
    let operations: OperationCenter
    @Binding var selection: String?

    @State private var target = ""

    var body: some View {
        VStack(spacing: 0) {
            addBar
            HairlineDivider()
            List(selection: $selection) {
                Section {
                    ForEach(projection.officialSources) { source in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text(source.explanation)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.38))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier(
                                    "official-tap-explanation-"
                                        + source.id.replacingOccurrences(of: "/", with: "-")
                                )
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    sectionHeader("Official sources")
                }

                Section {
                    ForEach(projection.thirdPartyTaps) { tap in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tap.name)
                                .font(Theme.mono(12.5, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text(TapProjection.packageSummary(for: tap))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.38))
                        }
                        .padding(.vertical, 2)
                        .tag(tap.name)
                        .themedListSelection(isSelected: selection == tap.name)
                    }

                    if case .content(isThirdPartyEmpty: true) = presentationState {
                        Text("No third-party taps are installed.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    sectionHeader("Third-party taps")
                }
            }
            .overlay { blockingState }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("taps-list")
        }
        .background(Color.white.opacity(0.014))
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
            HStack(spacing: 8) {
                TextField("user/repo", text: $target)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .padding(.horizontal, 10)
                    .frame(height: 28, alignment: .leading)
                    .background(
                        Theme.controlFill,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .accessibilityIdentifier("tap-add-field")
                    .onSubmit(addTap)
                Button("Add Tap", action: addTap)
                    .buttonStyle(TapActionButtonStyle(
                        fill: Theme.controlFillLoud,
                        text: Theme.textPrimary
                    ))
                    .disabled(addCommand == nil || !projection.canAddTap || !operations.isAvailable)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityIdentifier("tap-add-button")
            }
            if !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               addCommand == nil {
                Text("Enter a tap as user/repo.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
        }
        .padding(12)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Color.white.opacity(0.3))
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
