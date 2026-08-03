//
//  PackageMetadataSection.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SwiftUI

/// The three local, private things you can record about a package: a star, a
/// note, and a snooze of the update you are not ready for
/// (local-package-metadata LPM2, LPM3, LPM4, LPM5).
///
/// A separate view rather than three more methods on `PackageDetailView`: that
/// file is already at its length budget, and these three share one store, one
/// availability state and one reason string.
///
/// The view owns **no rule**. Whether the badge is suppressed is
/// `PackageMetadata.isSnoozed`, a pure function proven in the package's own
/// suite; all this decides is layout.
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
    private var isFavorite: Bool { stored?.isFavorite == true }
    private var isUnavailable: Bool { !metadata.availability.isAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    metadata.setFavorite(!isFavorite, for: entry.id)
                } label: {
                    Label(
                        isFavorite ? "Favorite" : "Add to favorites",
                        systemImage: isFavorite ? "star.fill" : "star"
                    )
                }
                snoozeControl
                Spacer(minLength: 0)
            }
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

    /// Snoozes the **currently offered** version, which is the whole of what a
    /// snooze stores: no duration, no expiry, no clock. When brew offers a
    /// different version the badge returns on its own, with no user action
    /// (design D5).
    @ViewBuilder
    private var snoozeControl: some View {
        if let installed = entry.installed, installed.isOutdated {
            let offered = installed.catalogVersion
            let isSnoozed = PackageMetadata.isSnoozed(
                offering: offered,
                snoozedVersion: stored?.snoozedVersion
            )
            Button {
                if isSnoozed {
                    metadata.unsnooze(entry.id)
                } else {
                    metadata.snooze(entry.id, offering: offered)
                }
            } label: {
                Label(
                    isSnoozed ? "Snoozed \(offered)" : "Snooze \(offered)",
                    systemImage: isSnoozed ? "bell.slash.fill" : "bell.slash"
                )
            }
            .help(
                isSnoozed
                    ? "Show the update badge for \(offered) again"
                    : "Hide the badge until a different version is offered"
            )
        }
    }

    /// A plain `TextEditor`: **no Markdown rendering and no length cap**.
    ///
    /// The note is stored and returned byte-identical, and it can reach no argv
    /// — argv comes only from `MutationCommand`. It also enters no search index:
    /// searching the Installed list for a word that appears only in a note
    /// returns nothing, by design (settled R4, LPM3 sc3).
    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Note").font(.headline)
            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 80)
                .focused($isEditing)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Private to this machine. Never sent anywhere.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
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
