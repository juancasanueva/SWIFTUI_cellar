import Foundation
import SecurityKit
import Testing

/// Where the optional NVD API key may and may not live.
///
/// The spec is unusually specific here — Keychain, not user defaults, not app
/// storage, not a plist, not a log — because every one of those alternatives is
/// somewhere a credential ends up readable by anything that can read the user's
/// home directory. The behavioural half of that is testable through the seam;
/// the "not anywhere else" half is not, because it is an absence, so it is
/// asserted structurally against the target's own source.
///
/// **No test here touches the real Keychain.**
@Suite("Advisory credential store")
struct CredentialStoreTests {
    // MARK: - The seam

    @Test("The key round-trips through the seam and never through user defaults")
    func theKeyRoundTripsThroughTheSeamAndNeverThroughUserDefaults() async throws {
        let store = InMemoryCredentialStore()

        #expect(try await store.apiKey() == nil, "a fresh store already held a key")

        try await store.store(apiKey: "nvd-key-under-test")
        #expect(try await store.apiKey() == "nvd-key-under-test")

        try await store.removeAPIKey()
        #expect(try await store.apiKey() == nil, "removal left the key behind")

        // The seam is the only reader, and it is actually read: `NVDSource`
        // consults it once per scan rather than caching it in a global.
        #expect(await store.readCount == 3)
    }

    /// The absence half, asserted against the source a reviewer reads.
    ///
    /// A behavioural test cannot prove a key never reaches `UserDefaults`,
    /// because the failure would be a call this test never makes. A structural
    /// scan can: if no file in the target so much as names `UserDefaults`, no
    /// call to it exists.
    @Test("The security target names no user-defaults, app-storage or logging API")
    func theSecurityTargetNamesNoDefaultsOrLoggingApi() throws {
        let sources = try SecurityKitSources.load()
        SecurityKitSources.assertAnchored(sources)

        for token in ["UserDefaults", "AppStorage", "NSUbiquitousKeyValueStore", "print",
                      "os_log", "OSLog", "Logger", "NSLog", "debugPrint", "dump"] {
            let offenders = sources.filter { $0.code.containsIdentifier(token) }
            #expect(
                offenders.isEmpty,
                "\(token) leaked into \(offenders.map(\.name).sorted())"
            )
        }
    }

    /// The scanner, pointed at source that does violate the rule, so the
    /// absences above are not the absences of a scanner that reads nothing.
    @Test(
        "The credential scanner detects each disallowed sink",
        arguments: [
            "UserDefaults.standard.set(key, forKey: \"nvd\")",
            "@AppStorage(\"nvd\") private var key = \"\"",
            "print(key)",
            "os_log(\"%@\", key)",
            "Logger().debug(\"\\(key)\")"
        ]
    )
    func theCredentialScannerDetectsEachDisallowedSink(violation: String) {
        let tokens = ["UserDefaults", "AppStorage", "print", "os_log", "Logger"]

        #expect(
            tokens.contains { violation.containsIdentifier($0) },
            "the scanner missed a real violation: \(violation)"
        )
    }

    // MARK: - The Keychain query

    /// The Keychain implementation is checked by its **query**, not by running
    /// it.
    ///
    /// Running it would prompt on a developer's machine, fail in CI, and leave a
    /// real credential behind. The three things that actually matter about this
    /// item — its class, its service, and when it becomes readable — are all
    /// decided in the query dictionary, so that is what is asserted.
    @Test("The Keychain item is a generic password, scoped and available after first unlock")
    func theKeychainItemIsAGenericPasswordScopedAndAvailableAfterFirstUnlock() {
        #expect(KeychainAdvisoryCredentialStore.service == "com.juancasanueva.cellar.nvd-api-key")

        let query = KeychainAdvisoryCredentialStore.baseQuery
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String
            == KeychainAdvisoryCredentialStore.service)

        // Not `WhenUnlocked`: a scheduled scan must be able to read the key while
        // the screen is locked. Not `Always`: the key stays unreadable until the
        // machine has been unlocked once since boot.
        #expect(
            KeychainAdvisoryCredentialStore.accessibility
                == kSecAttrAccessibleAfterFirstUnlock as String
        )
        // No synchronisation: this key belongs to this machine, and an iCloud
        // Keychain copy is a copy nobody asked for.
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
    }
}
