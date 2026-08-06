import Foundation
import ReleaseNotes
import Security
import Testing

/// Where the optional GitHub personal access token may and may not live.
///
/// The `CredentialStoreTests` idiom, applied to this capability's own item. The
/// behavioural half goes through the seam; the "not anywhere else" half is an
/// absence, so it is asserted structurally against the target's own source.
///
/// **No test here touches the real Keychain**, for the reason the shipped
/// advisory store already records: exercising it would prompt on a developer's
/// machine, fail in CI, and leave a real credential behind on whatever ran it.
/// What *is* asserted is the query dictionary, because every property that
/// matters about the item is decided there.
@Suite("Release-notes credential store")
struct ReleaseNotesCredentialStoreTests {
    // MARK: - The seam

    @Test("The token round-trips through the seam and removal leaves nothing")
    func theTokenRoundTripsThroughTheSeam() async throws {
        let store = InMemoryReleaseNotesCredentialStore()

        #expect(try await store.personalAccessToken() == nil, "a fresh store already held a token")

        try await store.store(personalAccessToken: "ghp_tokenUnderTest")
        #expect(try await store.personalAccessToken() == "ghp_tokenUnderTest")

        try await store.removePersonalAccessToken()
        #expect(try await store.personalAccessToken() == nil, "removal left the token behind")

        #expect(await store.readCount == 3)
    }

    // MARK: - The Keychain query

    @Test("The Keychain item is a generic password, scoped and available after first unlock")
    func theKeychainItemIsAGenericPasswordScopedAndAvailableAfterFirstUnlock() {
        #expect(
            KeychainReleaseNotesCredentialStore.service
                == "com.juancasanueva.cellar.github-pat"
        )

        let query = KeychainReleaseNotesCredentialStore.baseQuery
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(
            query[kSecAttrService as String] as? String
                == KeychainReleaseNotesCredentialStore.service
        )

        // Not `WhenUnlocked`: the sheet must be able to read the token whenever
        // the app is running. Not `Always`: it stays unreadable until the machine
        // has been unlocked once since boot.
        #expect(
            KeychainReleaseNotesCredentialStore.accessibility
                == kSecAttrAccessibleAfterFirstUnlock as String
        )
        // No synchronisation: this token belongs to this machine, and an iCloud
        // Keychain copy is a copy nobody asked for.
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)

        // The query identifies the item and does nothing else. A base query
        // carrying `kSecReturnData` would make every use of it a read.
        #expect(query[kSecReturnData as String] == nil)
        #expect(query[kSecValueData as String] == nil)
    }

    /// The distinctness claim, asserted here for the value this target owns.
    ///
    /// The cross-module half — that it differs from `KeychainAdvisoryCredentialStore.service`
    /// compared as **live symbols** rather than as two copied literals — lives in
    /// `cellarTests/ReleaseNotesEgressCompositionTests`, because this target may
    /// not see `SecurityKit` and the app test target is the only place that sees
    /// both. Recorded placement, not a silent absorption.
    @Test("The service name is this capability's own and names the credential it holds")
    func theServiceNameIsThisCapabilitysOwn() {
        let service = KeychainReleaseNotesCredentialStore.service

        #expect(service.hasPrefix("com.juancasanueva.cellar."))
        #expect(service.contains("github"))
        // The one it must not be. Asserted as a literal here and as a live symbol
        // comparison in the app test target: two independent ways to fail, so a
        // rename of either store cannot quietly collapse them onto one item.
        #expect(service != "com.juancasanueva.cellar.nvd-api-key")
    }

    // MARK: - Secret containment

    /// A behavioural test cannot prove a token never reaches `UserDefaults`,
    /// because the failure would be a call this test never makes. A structural
    /// scan can: if no file in the target so much as names the API, no call to it
    /// exists.
    @Test("The target names no user-defaults, app-storage or logging API")
    func theTargetNamesNoDefaultsOrLoggingApi() throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        for token in ["UserDefaults", "AppStorage", "NSUbiquitousKeyValueStore", "print",
                      "os_log", "OSLog", "Logger", "NSLog", "debugPrint", "dump"] {
            let offenders = sources.filter { $0.code.containsIdentifier(token) }
            #expect(
                offenders.isEmpty,
                "\(token) leaked into \(offenders.map(\.name).sorted())"
            )
        }
    }

    /// The scanner, pointed at source that *does* violate the rule, so the
    /// absences above are not the absences of a scanner that reads nothing.
    @Test(
        "The credential scanner detects each disallowed sink",
        arguments: [
            "UserDefaults.standard.set(token, forKey: \"pat\")",
            "@AppStorage(\"pat\") private var token = \"\"",
            "print(token)",
            "os_log(\"%@\", token)",
            "Logger().debug(\"\\(token)\")",
            "NSLog(\"%@\", token)"
        ]
    )
    func theCredentialScannerDetectsEachDisallowedSink(violation: String) {
        let tokens = ["UserDefaults", "AppStorage", "print", "os_log", "Logger", "NSLog"]

        #expect(
            tokens.contains { violation.containsIdentifier($0) },
            "the scanner missed a real violation: \(violation)"
        )
    }

    /// Comment stripping is what lets the target *document* its prohibitions in
    /// the directory the guard scans. `ReleaseNotes.swift` names `UserDefaults`
    /// and `@AppStorage` in prose; if stripping regressed, the guard would fail on
    /// its own documentation and the obvious "fix" would be deleting it.
    @Test("Prose naming a forbidden token is stripped, while code using it is not")
    func commentsAreStrippedButCodeIsNot() throws {
        let sources = try ReleaseNotesSources.load()
        let namespace = try #require(sources.first { $0.name == "ReleaseNotes.swift" })

        #expect(namespace.code.containsIdentifier("UserDefaults") == false)
        #expect(namespace.code.contains("cacheFileName"))
        #expect(namespace.code.contains("import Foundation"))

        // The stripper, pointed at a file that both documents and violates.
        let mixed = """
            // UserDefaults is forbidden here and this sentence explains why.
            let sink = UserDefaults.standard
            """
        let stripped = ReleaseNotesSources.stripComments(from: mixed)
        #expect(stripped.containsIdentifier("UserDefaults"), "stripping removed real code")
        #expect(stripped.contains("forbidden here") == false, "stripping left prose behind")
    }
}

// MARK: - The fake

/// The seam without a Keychain, and with a read counter.
///
/// The counter is not decoration: it is what proves the source consults the store
/// rather than caching a token in a global, which is the difference between
/// "remove works" and "remove works until the process restarts".
actor InMemoryReleaseNotesCredentialStore: ReleaseNotesCredentialStoring {
    private var token: String?
    private(set) var readCount = 0

    init(token: String? = nil) {
        self.token = token
    }

    func personalAccessToken() async throws -> String? {
        readCount += 1
        return token
    }

    func store(personalAccessToken: String) async throws {
        token = personalAccessToken
    }

    func removePersonalAccessToken() async throws {
        token = nil
    }
}
