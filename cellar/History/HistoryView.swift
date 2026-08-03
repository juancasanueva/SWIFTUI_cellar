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

    @State private var isClearing = false

    var body: some View {
        @Bindable var history = history
        return List {
            ForEach(history.records) { record in
                HistoryRow(record: record)
            }
        }
        .searchable(text: $history.search, prompt: "Search by package, verb or command")
        .overlay { emptyState }
        .navigationTitle(AppSection.history.title)
        .toolbar {
            Button("Clear History…", role: .destructive) { isClearing = true }
                .disabled(history.records.isEmpty || !history.availability.isAvailable)
        }
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

#Preview {
    HistoryView(history: HistoryStore(container: nil))
}
