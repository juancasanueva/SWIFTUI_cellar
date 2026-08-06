import Foundation

/// What this capability refuses to do, and why.
///
/// Deliberately **not** `AdvisoryError`. That type lives in `SecurityKit` and
/// belongs to the CVE scanner; importing it to reuse one case would couple
/// release notes to advisory scanning and would make one grant look like it could
/// authorise the other. Same rules, own type — which is the whole of D2 in one
/// declaration.
///
/// It carries only what `authorise()` can refuse with. Everything a *fetch* can
/// fail with is a `ReleaseNotesFailure`, because a failure that reaches the user
/// is a state to render rather than an error to throw, and mixing the two would
/// mean a call site could `catch` a rate limit.
public enum ReleaseNotesError: Error, Sendable, Hashable {
    /// No release-notes grant is recorded. Throwing rather than returning a
    /// boolean so the refusal has to be caught and shown.
    case blockedPendingConsent
}
