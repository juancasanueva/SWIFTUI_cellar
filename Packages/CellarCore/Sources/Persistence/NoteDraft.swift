import Foundation

/// A note being edited, and the one rule about when it owes a write.
///
/// The rule used to live in `PackageMetadataSection`: the draft was reset on a
/// package change with no commit, so anything typed and not yet committed by a
/// focus change was lost the moment the user clicked another package. A switch
/// is navigation, not a cancel, so it commits silently — there is deliberately
/// no prompt and no discard affordance (settled Q2).
///
/// Pure and store-free: it holds text and answers a question about text. The
/// view keeps layout only, the same discipline as `PackageMetadata.isSnoozed`
/// (design D7).
public struct NoteDraft: Sendable, Equatable {
    /// Verbatim, including newlines and leading whitespace. Nothing is trimmed:
    /// the note is stored and returned byte-identical.
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    /// What a newly shown package starts with.
    ///
    /// Absent and empty both start blank, because "no note" is one state rather
    /// than two — storing an empty note *is* having no note.
    public static func starting(from stored: String?) -> NoteDraft {
        NoteDraft(stored ?? "")
    }

    /// The write this draft owes against what is stored, or `nil` when it owes
    /// nothing.
    ///
    /// `nil` and `""` are different answers on purpose: owing nothing leaves
    /// the stored note alone, while owing `""` is what erases a note the user
    /// deleted the last character of.
    public func pendingWrite(against stored: String?) -> String? {
        text == (stored ?? "") ? nil : text
    }
}
