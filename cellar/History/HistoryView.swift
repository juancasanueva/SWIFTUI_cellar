//
//  HistoryView.swift
//  cellar
//

import Persistence
import SwiftUI

/// Every mutation Cellar performed, newest first and searchable
/// (installation-history IH5, IH6).
///
/// The search term is written straight onto the store, which re-runs its own
/// `FetchDescriptor`: the filtering is a predicate over the database rather than
/// a scan in the view, and an empty term returns **every** entry because
/// retention is keep-all and truncating the view would quietly contradict that.
///
/// Clearing is one confirmed, all-or-nothing action. There is no selective
/// deletion to offer instead, which is why the only destructive affordance here
/// is the whole thing.
struct HistoryView: View {
    let history: HistoryStore

    var body: some View {
        @Bindable var history = history
        return VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.system(size: 27, weight: .semibold))
                .kerning(-0.6)
                .foregroundStyle(Theme.textPrimary)
                .padding(EdgeInsets(top: 26, leading: 34, bottom: 14, trailing: 34))
            List {
                ForEach(history.records) { record in
                    HistoryRow(record: record)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.windowBackground)
        .overlay { emptyState }
        .navigationTitle(AppSection.history.title)
    }

    /// Three different emptinesses, and they mean different things: a store that
    /// would not open is a degraded state with a reason, a search that matched
    /// nothing is a normal result, and no entries at all is a new install.
    @ViewBuilder
    private var emptyState: some View {
        if let reason = history.availability.reason {
            ContentUnavailableView(
                "History is unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(reason)
            )
        } else if history.records.isEmpty, !history.search.isEmpty {
            ContentUnavailableView.search(text: history.search)
        } else if history.records.isEmpty {
            ContentUnavailableView(
                "No history yet",
                systemImage: AppSection.history.systemImage,
                description: Text("Package changes you make in Cellar are recorded here.")
            )
        }
    }
}

/// The section's search as a shell-bar field: in the pinned capsule rather
/// than `.searchable`, whose native toolbar placement floats over the bar.
struct HistorySearchField: View {
    @Bindable var history: HistoryStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.4))
            TextField("Search by package, verb or command", text: $history.search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .frame(maxWidth: 300)
        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityIdentifier("history-search-field")
    }
}

/// The section's one action as a shell-bar chip, owning its own confirmation
/// so the shell embeds one accessory and inherits the whole flow.
struct HistoryShellAccessories: View {
    let history: HistoryStore

    @State private var isClearing = false

    var body: some View {
        Button("Clear History…", systemImage: "trash") { isClearing = true }
            .buttonStyle(ShellChipButtonStyle(iconOnly: true))
            .help("Clear History")
            .disabled(history.records.isEmpty || !history.availability.isAvailable)
            .confirmationDialog(
                "Clear the whole history?",
                isPresented: $isClearing,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) { history.clearAll() }
                Button("Cancel", role: .cancel) { isClearing = false }
            } message: {
                Text(
                    """
                    This removes every recorded package change. \
                    Your favorites, notes and snoozes are not affected.
                    """
                )
            }
    }
}

#Preview {
    HistoryView(history: HistoryStore(container: nil))
}
