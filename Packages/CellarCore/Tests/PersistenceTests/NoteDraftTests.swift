import Foundation
import Testing

@testable import Persistence

/// When an in-progress note owes a write, and what it owes.
///
/// The rule lived in the view: `onChange(of: entry.id)` reset the draft with no
/// commit at all, so anything typed and not yet committed by a focus change was
/// simply gone when the user clicked another package. Extracted as a pure value
/// so the rule is provable in the `swift test` loop and the view keeps layout
/// only — the `PackageMetadata.isSnoozed` discipline (design D7).
@Suite("Note draft")
struct NoteDraftTests {
    @Test("An edited draft owes a write when the shown package changes")
    func anEditedDraftOwesAWriteWhenTheShownPackageChanges() {
        let draft = NoteDraft("build from source, not the bottle")

        #expect(draft.pendingWrite(against: nil) == "build from source, not the bottle")
        #expect(draft.pendingWrite(against: "") == "build from source, not the bottle")
        #expect(draft.pendingWrite(against: "an older note") == "build from source, not the bottle")
    }

    @Test("An unchanged draft owes no write")
    func anUnchangedDraftOwesNoWrite() {
        #expect(NoteDraft("keep this one").pendingWrite(against: "keep this one") == nil)
        // No stored note and nothing typed is the ordinary case for a package
        // that was only looked at: it must not write an empty row.
        #expect(NoteDraft("").pendingWrite(against: nil) == nil)
        #expect(NoteDraft("").pendingWrite(against: "") == nil)
        // Verbatim, so whitespace and newlines are a difference like any other.
        #expect(NoteDraft("line one\nline two").pendingWrite(against: "line one\nline two") == nil)
        #expect(NoteDraft(" trailing ").pendingWrite(against: "trailing") == " trailing ")
    }

    @Test("An emptied draft owes a write that clears the note")
    func anEmptiedDraftOwesAWriteThatClearsTheNote() {
        // Not `nil`: owing nothing and owing "store the empty note" are
        // different answers, and only the second erases what is on disk.
        #expect(NoteDraft("").pendingWrite(against: "a note that should go away") == "")
    }

    @Test("A newly shown package starts from whatever it has stored")
    func aNewlyShownPackageStartsFromWhatItHasStored() {
        #expect(NoteDraft.starting(from: "stored note") == NoteDraft("stored note"))
        #expect(NoteDraft.starting(from: "stored note").text == "stored note")
        // Absent and empty both start blank — "no note" is one state.
        #expect(NoteDraft.starting(from: nil).text == "")
        #expect(NoteDraft.starting(from: "").text == "")
        // And a draft that just started owes nothing against the same source.
        #expect(NoteDraft.starting(from: "stored note").pendingWrite(against: "stored note") == nil)
        #expect(NoteDraft.starting(from: nil).pendingWrite(against: nil) == nil)
    }
}
