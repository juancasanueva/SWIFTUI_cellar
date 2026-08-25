import BrewClient
import Catalog
import SwiftUI

struct TapsListView: View {
    let taps: TapStore
    /// The per-package grant report. Read only: this view shows what Homebrew
    /// records and offers no control that would change it (package-trust PT7).
    let trustGrants: TrustGrantStore
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
                        // Selectable like a tap row, with the same highlight:
                        // the selection opens the read-only official pane,
                        // never the third-party detail (TM4).
                        .tag(source.id)
                        .themedListSelection(isSelected: selection == source.id)
                    }
                } header: {
                    sectionHeader("Official sources")
                }

                Section {
                    ForEach(projection.thirdPartyTaps) { tap in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(tap.name)
                                    .font(Theme.mono(12.5, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                // The badge text comes from the one projection
                                // the detail header also reads, so the two
                                // surfaces cannot drift (TM12).
                                if let badge = TapProjection.trust(for: tap).badge {
                                    TapTrustBadge(text: badge, identifier: "tap-row-trust-badge")
                                }
                            }
                            HStack(spacing: 5) {
                                Text(TapProjection.packageSummary(for: tap))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.white.opacity(0.38))
                                // An **added** component beside the summary, from
                                // the same projection value the detail header
                                // reads. It never replaces the summary and never
                                // touches the badge (TM12 :70-75).
                                if let countLine = grants(for: tap).countLine {
                                    Text("·")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.white.opacity(0.25))
                                    Text(countLine)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.white.opacity(0.38))
                                        .accessibilityIdentifier("tap-row-grant-count")
                                }
                            }
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

                // Everything the report records that no installed tap accounts
                // for. Shown rather than only counted, because a grant that
                // survived an untap is exactly the one worth seeing (PT4, PT8).
                if grantSection.sentence != nil || !grantSection.groups.isEmpty {
                    Section {
                        if let sentence = grantSection.sentence {
                            Text(sentence)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.38))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("tap-grant-section-sentence")
                        }
                        ForEach(grantSection.groups) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.3))
                                ForEach(group.entries, id: \.self) { entry in
                                    Text(entry)
                                        .font(Theme.mono(11.5))
                                        .foregroundStyle(Theme.textMono)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        sectionHeader(grantSection.title)
                    }
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
                  TapProjection.officialSource(named: selection) != nil
                      || inventory.taps.contains(where: { $0.name == selection })
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

    /// The one projection value this row and the detail header both read, so
    /// the two cannot drift (package-trust PT5, DD-6).
    private func grants(for tap: TapRecord) -> TapProjection.TapGrantPresentation {
        TapProjection.grants(for: tap, in: trustGrants.grants)
    }

    private var grantSection: TrustGrantSection {
        TapProjection.unattributedSection(in: trustGrants.grants, taps: taps.inventory.taps)
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
