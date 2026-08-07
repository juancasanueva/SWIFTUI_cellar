//
//  PackageMetadataSection.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SwiftUI

/// The private note (local-package-metadata LPM3), in the design's NOTES well.
///
/// This section used to carry the favorite and snooze affordances as well; the
/// design port moved the favorite to the header's heart and the snooze into
/// the Actions row, both writing through the same store. What remains here is
/// the note — with the same commit discipline it always had.
///
/// The view owns **no rule**; `NoteDraft` decides what a commit owes.
struct PackageMetadataSection: View {
    let entry: PackageEntry
    let metadata: MetadataStore

    /// Local, so typing does not write a row per keystroke.
    ///
    /// Committed when **focus leaves the field** and when the **shown package
    /// changes**. Those are the only two triggers there are: a multiline
    /// `TextEditor` has no `onSubmit`, so the commit this comment used to claim
    /// happened on submit never existed. Whether a commit is owed at all is
    /// `NoteDraft.pendingWrite(against:)`, proven in the package's own suite.
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    private var stored: PackageMetadata? { metadata.snapshot[entry.id] }
    private var isUnavailable: Bool { !metadata.availability.isAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            noteEditor
            if let reason = metadata.availability.reason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(isUnavailable)
        .onAppear { draft = NoteDraft.starting(from: stored?.note).text }
        // Against `oldValue`, and before the reset: `stored` already reads the
        // package being switched *to*, so the closure's own `oldValue` is the
        // only place the departing package's identity still exists.
        .onChange(of: entry.id) { oldValue, _ in
            commit(for: oldValue, against: metadata.snapshot[oldValue]?.note)
            draft = NoteDraft.starting(from: stored?.note).text
        }
    }

    /// A plain `TextEditor`: **no Markdown rendering and no length cap**.
    ///
    /// The note is stored and returned byte-identical, and it can reach no argv
    /// — argv comes only from `MutationCommand`. It also enters no search index:
    /// searching the Installed list for a word that appears only in a note
    /// returns nothing, by design (settled R4, LPM3 sc3).
    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.system(size: 11, weight: .bold))
                .kerning(0.66)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.34))
            TextEditor(text: $draft)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64)
                .padding(EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9))
                .background(
                    Color.black.opacity(0.24),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                )
                .focused($isEditing)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Add a private note about why you keep this around…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.top, 15)
                            .padding(.leading, 14)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: isEditing) { _, editing in
                    guard !editing else { return }
                    commit(for: entry.id, against: stored?.note)
                }
        }
    }

    /// Writes the draft against `id`, if it owes anything.
    ///
    /// Both the stored note and the identity are parameters rather than read
    /// from `entry`, because the package-change trigger has to commit against
    /// the one being *left*. Verbatim, including newlines and leading
    /// whitespace; an emptied draft writes `""`, which is what clears the note.
    private func commit(for id: PackageID, against storedNote: String?) {
        guard let pending = NoteDraft(draft).pendingWrite(against: storedNote) else { return }
        metadata.setNote(pending, for: id)
    }
}
