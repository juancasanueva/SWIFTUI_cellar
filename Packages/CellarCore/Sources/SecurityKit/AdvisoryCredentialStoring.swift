import Foundation

/// Where the optional NVD API key lives.
///
/// A seam rather than a direct Keychain call at the point of use, for two
/// reasons that pull in the same direction. The obvious one is testability: no
/// test in this package may touch the real Keychain, and an in-memory conformer
/// makes that structural rather than aspirational. The load-bearing one is that
/// a *named* seam is the thing a structural guard can point at — the key must
/// never reach `UserDefaults`, `@AppStorage`, a plist or a log, and the way to
/// keep that true is for there to be exactly one way to read it.
///
/// The key is optional throughout. NVD answers unauthenticated requests at a
/// lower rate limit, so a missing key degrades the *cadence* of enrichment and
/// nothing else — it never degrades an answer into a guess.
public protocol AdvisoryCredentialStoring: Sendable {
    /// The stored key, or `nil` when the user has not supplied one.
    func apiKey() async throws -> String?
    func store(apiKey: String) async throws
    func removeAPIKey() async throws
}
