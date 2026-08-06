//
//  ReleaseNotesEgressCompositionTests.swift
//  cellarTests
//

import BrewClient
import BrewProcess
import Catalog
import Foundation
import ReleaseNotes
import SecurityKit
import Testing

@testable import cellar

/// Two claims that **cannot** be made inside `CellarCore`, made here.
///
/// This is a recorded placement, not a convenience. `ReleaseNotes` depends on
/// `Catalog` alone, so it can see neither `BrewClient` (where `OperationCenterBulk`
/// lives) nor `SecurityKit` (where the advisory Keychain item lives). The app test
/// target is the only place in the repository that sees all three, so it is the
/// only place these two assertions can be written at all.
///
/// That absence of an edge is also *why* both claims hold. The guards exist to
/// notice if someone adds one.
@Suite("Release-notes egress composition")
struct ReleaseNotesEgressCompositionTests {
    // MARK: - A bulk upgrade issues zero GitHub requests

    /// Thirty outdated packages, upgraded in one bulk operation, with a granted
    /// consent and a recording transport: **zero** release-notes requests.
    ///
    /// The grant is the interesting part of the arrangement. With consent
    /// withheld the zero would be trivially true and would prove only that the
    /// consent gate works. Granted, it proves the shape: there is no path from
    /// `OperationCenterBulk` to this capability, because there is no edge in the
    /// build graph and no plural entry point to reach for if there were.
    ///
    /// The control is in the **same test**, over the **same store and the same
    /// transport**: asked explicitly, that store issues exactly one request. So
    /// the zero is the zero of a live capability bulk work cannot reach, and not
    /// the zero of a store nobody wired up. It uses a per-instance recorder
    /// rather than the process-global `CompositionRequestSpy`, because a test
    /// that *makes* a request to prove a global counter works will clobber a
    /// concurrent test asserting that counter is zero — which is exactly what
    /// happened, in alternation, until this recorder existed.
    @Test("Thirty bulk upgrades issue zero release-notes requests and never touch the store")
    @MainActor
    func thirtyBulkUpgradesIssueZeroReleaseNotesRequests() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-bulk-egress-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let network = CompositionNetwork()
        // A granted consent, so a path from bulk work to egress would actually
        // be taken rather than refused at the gate.
        let store = ReleaseNotesStore(
            source: GitHubReleaseNotesSource(session: network.session),
            cache: ReleaseNotesCache(
                fileURL: directory.appendingPathComponent(ReleaseNotes.cacheFileName)
            ),
            consent: FixedReleaseNotesConsent(.granted(at: Date(timeIntervalSince1970: 1))),
            credentials: nil
        )

        let center = OperationCenter(launcherFactory: { _ in AppTestProcessLauncher() })
        let ids = (0..<30).map { PackageID(kind: .formula, name: "outdated-\($0)") }

        let submitted = center.submitUpgrades(for: ids)

        // Anchored positively: the bulk operation really did run, so the zeros
        // below are the zeros of work that happened.
        #expect(submitted.count == 30, "the bulk submission produced \(submitted.count) items")

        #expect(network.requestCount == 0, "a bulk upgrade issued \(network.requestCount) requests")
        // And the store was never touched: every package is still `.idle`, and
        // nothing was published into it.
        #expect(store.states.isEmpty, "a bulk upgrade populated the release-notes store")
        #expect(store.rateLimit == nil)
        for id in ids {
            #expect(store.state(for: id) == .idle)
        }
        // Nothing was written to the cache directory either — no file, and not
        // even the directory itself.
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)

        // The control: the same store, asked the way a click asks, does reach the
        // network exactly once.
        store.load(
            ids[0],
            version: "1.0.0",
            candidates: RepositoryCandidates(
                homepage: "https://github.com/acme/foo",
                headURL: nil, stableURL: nil, caskDownloadURL: nil
            )
        )
        await store.waitForLoad(ids[0])

        #expect(network.requestCount == 1, "an explicit load issued \(network.requestCount) requests")
        #expect(store.states.isEmpty == false, "an explicit load published nothing")
    }

    /// The other half of the shape claim: `OperationCenterBulk` takes a
    /// `[PackageID]` and this capability has no such surface anywhere, so there
    /// is nothing for a bulk caller to reach.
    @Test("The release-notes store exposes no plural entry point a bulk caller could use")
    func theStoreExposesNoPluralEntryPoint() throws {
        let sources = try AppSecuritySources.load()
        let composition = sources.filter { $0.name.hasPrefix("ReleaseNotes") }

        #expect(composition.isEmpty == false, "the scan found no release-notes app source")

        for source in composition {
            for token in ["[PackageID]", "submitBulk", "prefetch", "loadAll"] {
                #expect(
                    source.code.contains(token) == false,
                    "\(token) appears in \(source.name)"
                )
            }
        }
    }

    /// And no ambient trigger on the path that can reach the network.
    ///
    /// Stated precisely rather than broadly, because a broad ban would be wrong:
    /// `ReleaseNotesConsentSheet` legitimately uses `.task` to read the Keychain
    /// for its own status line, and banning `.task` outright would either fail on
    /// that or push it into a more obscure spelling. What must not exist is a
    /// trigger on the path to `store.load`, so the claim is made about **that**:
    /// `load(` is called from exactly one file, and that file has no ambient
    /// trigger at all.
    @Test("The only caller of the store's load is one button, with no ambient trigger near it")
    func theOnlyCallerOfLoadIsOneButton() throws {
        let sources = try AppSecuritySources.load()
        let callers = sources.filter {
            $0.code.contains("store?.load(") || $0.code.contains("store.load(")
        }

        #expect(
            callers.map(\.name) == ["ReleaseNotesSection.swift"],
            "the store's load is called from \(callers.map(\.name).sorted())"
        )

        let caller = try #require(callers.first)
        for trigger in [".task {", ".task(", ".onAppear", ".onHover", ".onChange", ".onReceive"] {
            #expect(
                caller.code.contains(trigger) == false,
                "\(caller.name) starts work from \(trigger)"
            )
        }
        // Anchored: that file really does call load, and really does declare a
        // button — so the absences above are absences in a file that matters.
        #expect(caller.code.contains("store?.load("))
        #expect(caller.code.contains("Button("))
    }

    /// The consent sheet's one `.task` reaches the **Keychain**, not the network.
    /// Named here so the narrowing above is a recorded judgement rather than a
    /// hole somebody quietly widened.
    @Test("The consent sheet's task reads the Keychain and nothing else")
    func theConsentSheetsTaskReadsTheKeychain() throws {
        let sources = try AppSecuritySources.load()
        let sheet = try #require(sources.first { $0.name == "ReleaseNotesConsentSheet.swift" })

        #expect(sheet.code.contains("await readTokenStatus()"))
        #expect(sheet.code.contains("load(") == false, "the consent sheet can start a fetch")
        #expect(sheet.code.contains("URLSession") == false)
    }

    // MARK: - Two credentials, two homes

    /// Compared as **live symbols**, not as two copied string literals.
    ///
    /// A test that wrote both names out by hand would keep passing after somebody
    /// renamed one store and forgot the other, which is precisely the situation
    /// where two credentials silently collapse onto one Keychain item — and where
    /// removing a GitHub token would take an NVD key with it.
    @Test("The two Keychain service names are different, compared as live symbols")
    func theTwoKeychainServiceNamesAreDifferent() {
        #expect(
            KeychainReleaseNotesCredentialStore.service
                != KeychainAdvisoryCredentialStore.service,
            "the two capabilities share one Keychain item"
        )

        // Anchored: both are real, non-empty, and scoped to this app — so the
        // inequality above is not the inequality of two empty strings.
        for service in [
            KeychainReleaseNotesCredentialStore.service,
            KeychainAdvisoryCredentialStore.service
        ] {
            #expect(service.hasPrefix("com.juancasanueva.cellar."))
            #expect(service.count > "com.juancasanueva.cellar.".count)
        }
    }

    /// The same distinctness for the **grant**, which lives in defaults rather
    /// than the Keychain: consenting to advisory scanning must not consent to
    /// GitHub, and neither key may be read as the other.
    @Test("The two consent preferences use different defaults keys")
    @MainActor
    func theTwoConsentPreferencesUseDifferentDefaultsKeys() {
        #expect(ReleaseNotesConsentPreference.grantedKey != SecurityConsentPreference.grantedKey)
        #expect(ReleaseNotesConsentPreference.grantedAtKey != SecurityConsentPreference.grantedAtKey)
        #expect(ReleaseNotesConsentPreference.grantedKey.isEmpty == false)
        #expect(SecurityConsentPreference.grantedKey.isEmpty == false)
    }

    /// And the grants themselves are different types, so no amount of wiring can
    /// pass one where the other is required.
    @Test("A granted security scan does not produce a release-notes grant")
    @MainActor
    func aGrantedSecurityScanDoesNotProduceAReleaseNotesGrant() async throws {
        let defaults = try #require(UserDefaults(suiteName: "release-notes-grant-\(UUID().uuidString)"))
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        let scan = SecurityConsentPreference(defaults: defaults)
        let notes = ReleaseNotesConsentPreference(defaults: defaults)

        scan.grant()

        #expect(scan.isGranted)
        // The security grant left this one untouched: separate keys, separate
        // questions, separate answers.
        #expect(notes.isGranted == false)
        #expect(await notes.currentConsent() == .notGranted)
        #expect(throws: ReleaseNotesError.blockedPendingConsent) {
            try notes.consent.authorise()
        }
    }
}
