import Foundation
import Security

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

/// Something the Keychain refused to do.
///
/// Carries the raw `OSStatus` because a Keychain failure is almost always a
/// configuration problem — entitlements, an unsigned build, a locked keychain —
/// and the status code is the only thing that tells them apart. The **key** is
/// never in here.
public struct KeychainFailure: Error, Sendable, Hashable {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }
}

/// The real thing: one generic-password item, scoped to this app.
///
/// ## Why the query is exposed and the calls are not tested
///
/// Exercising this type would prompt on a developer's machine, fail in CI, and
/// leave a real credential behind on whatever ran it. So no test calls it. What
/// *is* asserted is the query dictionary, because the three things that matter
/// about this item are all decided there: it is a generic password, it is scoped
/// to one service name, and it becomes readable after first unlock rather than
/// only while the screen is unlocked — a scheduled scan has to work on a locked
/// machine.
///
/// `kSecAttrSynchronizable` is explicitly `false`. An iCloud Keychain copy would
/// spread a credential to every device the user owns, which is not something
/// entering an NVD API key asks for.
public struct KeychainAdvisoryCredentialStore: AdvisoryCredentialStoring {
    public static let service = "com.juancasanueva.cellar.nvd-api-key"
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

    public func apiKey() async throws -> String? {
        var query = Self.baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func store(apiKey: String) async throws {
        // Replace rather than update-or-add: one item, one meaning, and no path
        // where a stale item survives beside a new one.
        try await removeAPIKey()

        var attributes = Self.baseQuery
        attributes[kSecValueData as String] = Data(apiKey.utf8)
        attributes[kSecAttrAccessible as String] = Self.accessibility

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
    }

    public func removeAPIKey() async throws {
        let status = SecItemDelete(Self.baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainFailure(status: status)
        }
    }
}
