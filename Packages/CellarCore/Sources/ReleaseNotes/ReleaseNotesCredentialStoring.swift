import Foundation
import Security

/// Where the optional GitHub personal access token lives.
///
/// A seam rather than a direct Keychain call at the point of use, for the two
/// reasons `AdvisoryCredentialStoring` already records and that apply verbatim
/// here: no test in this package may touch the real Keychain, and a *named* seam
/// is the thing a structural guard can point at. The token must never reach
/// `UserDefaults`, a plist or a log, and the way to keep that true is for there
/// to be exactly one way to read it.
///
/// The token is optional throughout. GitHub answers unauthenticated requests at
/// 60 per hour and authenticated ones at 5,000, so a missing token degrades the
/// **budget** and nothing else — it never blocks a request and never degrades an
/// answer into a guess.
public protocol ReleaseNotesCredentialStoring: Sendable {
    /// The stored token, or `nil` when the user has not supplied one.
    func personalAccessToken() async throws -> String?
    func store(personalAccessToken: String) async throws
    func removePersonalAccessToken() async throws
}

/// Something the Keychain refused to do.
///
/// Carries the raw `OSStatus` because a Keychain failure is almost always a
/// configuration problem — entitlements, an unsigned build, a locked keychain —
/// and the status code is the only thing that tells them apart. The **token** is
/// never in here.
public struct ReleaseNotesKeychainFailure: Error, Sendable, Hashable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }
}

/// The real thing: one generic-password item, scoped to this capability.
///
/// ## Why this is a second store and not a shared one
///
/// One mechanism applied twice, not a second set of rules (D2). The item shape,
/// the accessibility class and the synchronisation setting are identical to
/// `KeychainAdvisoryCredentialStore`'s; what differs is the **service name**, and
/// it differs because these are two credentials for two hosts. A shared item
/// would mean revoking a GitHub token also removed an NVD key, and would mean a
/// bug in either capability could read the other's secret.
///
/// ## Why the query is exposed and the calls are not tested
///
/// Exercising this type would prompt on a developer's machine, fail in CI, and
/// leave a real credential behind on whatever ran it. So no test calls it. What
/// *is* asserted is the query dictionary, because the three things that matter
/// about this item are all decided there: it is a generic password, it is scoped
/// to one service name, and it becomes readable after first unlock rather than
/// only while the screen is unlocked.
///
/// `kSecAttrSynchronizable` is explicitly `false`. An iCloud Keychain copy would
/// spread a credential to every device the user owns, which is not something
/// pasting a GitHub token into one Mac asks for.
public struct KeychainReleaseNotesCredentialStore: ReleaseNotesCredentialStoring {
    /// Distinct from the advisory item's `com.juancasanueva.cellar.nvd-api-key`.
    /// Asserted here as a literal, and in the app's test target as a live symbol
    /// comparison against the other store — two independent ways to fail, so a
    /// rename cannot quietly collapse the two credentials onto one item.
    public static let service = "com.juancasanueva.cellar.github-pat"
    public static let accessibility = kSecAttrAccessibleAfterFirstUnlock as String

    /// Everything that identifies the item, and nothing that reads or writes it.
    public static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword as String,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false
        ]
    }

    public init() {}

    public func personalAccessToken() async throws -> String? {
        var query = Self.baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ReleaseNotesKeychainFailure(status: status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func store(personalAccessToken: String) async throws {
        // Replace rather than update-or-add: one item, one meaning, and no path
        // where a stale token survives beside a new one.
        try await removePersonalAccessToken()

        var attributes = Self.baseQuery
        attributes[kSecValueData as String] = Data(personalAccessToken.utf8)
        attributes[kSecAttrAccessible as String] = Self.accessibility

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw ReleaseNotesKeychainFailure(status: status) }
    }

    public func removePersonalAccessToken() async throws {
        let status = SecItemDelete(Self.baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ReleaseNotesKeychainFailure(status: status)
        }
    }
}
