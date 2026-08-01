import Foundation

/// Every way a catalog sync can fail, as a closed set.
///
/// The taxonomy is deliberately coarse: a consumer renders one of five
/// sentences, and none of them require knowing anything about URLSession, the
/// file system, or JSON. Transport detail (timeouts, DNS, TLS) collapses into
/// `offline` because the user-facing remedy is identical.
public enum CatalogSyncError: Error, Sendable, Hashable {
    /// The request never produced a response — no route, timeout, TLS failure.
    case offline
    /// The origin answered with a status the sync cannot use.
    case httpStatus(Int)
    /// The body was unreadable as JSON, or held zero usable records.
    ///
    /// A payload that blows the size cap lands here too: it is a payload the
    /// sync refuses to parse, not a transport fault the user can retry away.
    case malformedPayload
    /// The snapshot could not be written; the previous one is untouched.
    case persistence
    /// The caller cancelled the sync.
    case cancelled

    /// Whether a backoff retry has any chance of a different answer.
    ///
    /// Transport faults, `429` and `5xx` are transient by definition. Every
    /// other `4xx` is the origin telling us the request itself is wrong, so
    /// repeating it only burns time.
    public var isRetryable: Bool {
        switch self {
        case .offline:
            true
        case .httpStatus(let status):
            status == 429 || (500...599).contains(status)
        case .malformedPayload, .persistence, .cancelled:
            false
        }
    }
}

/// Observable sync progress, as a closed set.
///
/// A consumer renders this without inspecting transport internals — that is the
/// whole point of publishing a status rather than a `URLSessionTask`.
public enum CatalogSyncStatus: Sendable, Equatable {
    case idle
    /// `fractionCompleted` is absent when the origin sends no `Content-Length`.
    case downloading(fractionCompleted: Double?)
    case decoding
    case succeeded(at: Date)
    case failed(CatalogSyncError)
}
