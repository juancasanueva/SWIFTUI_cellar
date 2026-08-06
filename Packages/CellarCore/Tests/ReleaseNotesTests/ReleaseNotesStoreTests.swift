import Catalog
import Foundation
import ReleaseNotes
import Testing

/// The store, and the budget it is answerable for.
///
/// Two claims run through everything here and they are not the same claim. The
/// first is about **correctness under supersession**: a second click for the same
/// package must cancel the first, only the later result may land, and a failed
/// reload must never blank a note the user is already reading. The second is
/// about **cost**: one opened request is one request, a cache hit is zero, and a
/// refusal is zero — counted below `URLSession`, not asserted about a fake.
@MainActor
@Suite("Release-notes store")
struct ReleaseNotesStoreTests {
    // MARK: - Arrangement

    private var packageID: PackageID { PackageID(kind: .formula, name: "hyperfine") }

    private var candidates: RepositoryCandidates {
        RepositoryCandidates(
            homepage: "https://github.com/sharkdp/hyperfine",
            headURL: nil,
            stableURL: nil,
            caskDownloadURL: nil
        )
    }

    private var unresolvableCandidates: RepositoryCandidates {
        RepositoryCandidates(
            homepage: "https://gnu.org/software/foo",
            headURL: nil,
            stableURL: nil,
            caskDownloadURL: nil
        )
    }

    private func cacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-release-notes-store-\(UUID().uuidString)")
            .appendingPathComponent("release-notes-v1.json")
    }

    private func store(
        _ network: RecordingNetwork,
        consent: ReleaseNotesConsent = .granted(at: Date(timeIntervalSince1970: 1_000_000)),
        token: String? = nil,
        cacheURL: URL? = nil,
        now: Date = Date(timeIntervalSince1970: 1_786_000_000)
    ) -> ReleaseNotesStore {
        ReleaseNotesStore(
            source: GitHubReleaseNotesSource(session: network.session),
            cache: ReleaseNotesCache(fileURL: cacheURL ?? self.cacheURL()),
            consent: FixedReleaseNotesConsent(consent),
            credentials: InMemoryReleaseNotesCredentialStore(token: token),
            now: { now }
        )
    }

    private func populatedPage() throws -> RecordingURLProtocol.Stub {
        .releases(try Fixture.data("GitHub/releases-git-populated.json"), etag: "\"page-1\"")
    }

    /// Awaits the store settling out of `.loading` without sleeping on a wall
    /// clock: the store exposes its in-flight work so a test can join it.
    private func settled(_ store: ReleaseNotesStore, _ id: PackageID) async -> ReleaseNotesState {
        await store.waitForLoad(id)
        return store.state(for: id)
    }

    // MARK: - Exactly one request

    @Test("One load issues exactly one request and lands a matched release")
    func oneLoadIssuesExactlyOneRequest() async throws {
        let network = RecordingNetwork(queue: [try populatedPage()])
        let store = store(network)

        store.load(packageID, version: "1.18.0", candidates: candidates)
        let state = await settled(store, packageID)

        guard case .loaded(.notes(let resolved, let release)) = state else {
            Issue.record("the load settled as \(state)")
            return
        }
        #expect(resolved.repository.slug == "sharkdp/hyperfine")
        #expect(release.tagName == "v1.18.0")
        #expect(network.requestCount == 1, "one load issued \(network.requestCount) requests")
    }

    @Test("An immediate second load for the same repository and version issues zero requests")
    func aSecondLoadForTheSameKeyIssuesZeroRequests() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let network = RecordingNetwork(queue: [try populatedPage(), try populatedPage()])
        let store = store(network, cacheURL: url)

        store.load(packageID, version: "1.18.0", candidates: candidates)
        _ = await settled(store, packageID)
        #expect(network.requestCount == 1)

        store.load(packageID, version: "1.18.0", candidates: candidates)
        let second = await settled(store, packageID)

        #expect(network.requestCount == 1, "the cache hit still issued a request")
        guard case .loaded(.notes(_, let release)) = second else {
            Issue.record("the cached load settled as \(second)")
            return
        }
        #expect(release.tagName == "v1.18.0")
    }

    /// A *different version* of the same repository is a different key, so it
    /// costs a request. Without this, the zero above could be a store that never
    /// asks twice for anything.
    @Test("A different version of the same repository is a miss and costs one request")
    func aDifferentVersionIsAMissAndCostsARequest() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let network = RecordingNetwork(queue: [try populatedPage(), try populatedPage()])
        let store = store(network, cacheURL: url)

        store.load(packageID, version: "1.18.0", candidates: candidates)
        _ = await settled(store, packageID)

        store.load(packageID, version: "1.19.0", candidates: candidates)
        let second = await settled(store, packageID)

        #expect(network.requestCount == 2)
        #expect(second.outcome?.release?.tagName == "v1.19.0")
    }

    @Test("A resolution failure issues zero requests and settles as unresolvable")
    func aResolutionFailureIssuesZeroRequests() async throws {
        let network = RecordingNetwork(queue: [try populatedPage()])
        let store = store(network)

        store.load(packageID, version: "1.18.0", candidates: unresolvableCandidates)
        let state = await settled(store, packageID)

        guard case .loaded(.unresolvableRepository(let tried)) = state else {
            Issue.record("an unresolvable package settled as \(state)")
            return
        }
        #expect(tried == Set(RepositorySource.allCases))
        #expect(network.requestCount == 0, "resolution failure issued a request")
    }

    @Test("A consent refusal issues zero requests and settles as blocked pending consent")
    func aConsentRefusalIssuesZeroRequests() async throws {
        let network = RecordingNetwork(queue: [try populatedPage()])
        let store = store(network, consent: .notGranted)

        store.load(packageID, version: "1.18.0", candidates: candidates)
        let state = await settled(store, packageID)

        #expect(state.outcome == .unavailable(.blockedPendingConsent))
        #expect(network.requestCount == 0, "an unconsented load issued a request")
    }

    /// A revoked grant is the same refusal, which is what "revocation leaves no
    /// residue" means at this layer.
    @Test("A revoked grant issues zero requests")
    func aRevokedGrantIssuesZeroRequests() async throws {
        let network = RecordingNetwork(queue: [try populatedPage()])
        let store = store(
            network,
            consent: ReleaseNotesConsent.granted(at: Date(timeIntervalSince1970: 1)).revoked()
        )

        store.load(packageID, version: "1.18.0", candidates: candidates)
        let state = await settled(store, packageID)

        #expect(state.outcome == .unavailable(.blockedPendingConsent))
        #expect(network.requestCount == 0)
    }

    @Test("A rate-limited outcome issues no retry")
    func aRateLimitedOutcomeIssuesNoRetry() async throws {
        let network = RecordingNetwork(queue: [.rateLimited()], fallback: .rateLimited())
        let store = store(network)

        store.load(packageID, version: "1.18.0", candidates: candidates)
        let state = await settled(store, packageID)

        let failure = try #require(state.outcome?.failure)
        #expect(failure.isRateLimited)
        #expect(network.requestCount == 1, "the refusal was retried \(network.requestCount) times")
        // And it was **not** written to the cache, so a later load re-asks rather
        // than replaying a wall that may have lifted.
        store.load(packageID, version: "1.18.0", candidates: candidates)
        _ = await settled(store, packageID)
        #expect(network.requestCount == 2, "a rate-limit refusal was served from the cache")
    }

    // MARK: - The four absences reach the surface intact

    @Test("An empty releases list settles as publishes-no-releases, not as a failure")
    func anEmptyListSettlesAsPublishesNoReleases() async throws {
        let network = RecordingNetwork(queue: [
            .releases(try Fixture.data("GitHub/releases-empty.json"))
        ])
        let store = store(network)

        store.load(packageID, version: "1.18.0", candidates: candidates)
        let state = await settled(store, packageID)

        guard case .loaded(.repositoryPublishesNoReleases(let resolved)) = state else {
            Issue.record("an empty list settled as \(state)")
            return
        }
        #expect(resolved.repository.slug == "sharkdp/hyperfine")
    }

    @Test("A non-empty page with no matching tag carries the inspected count and page bound")
    func aNonEmptyPageWithNoMatchCarriesItsEvidence() async throws {
        let network = RecordingNetwork(queue: [
            .releases(try Fixture.data("GitHub/releases-git-populated.json"))
        ])
        let store = store(network)

        store.load(packageID, version: "99.0.0", candidates: candidates)
        let state = await settled(store, packageID)

        guard case .loaded(.noReleaseMatchesVersion(_, let version, let inspected, let full))
            = state
        else {
            Issue.record("an unmatched page settled as \(state)")
            return
        }
        #expect(version == "99.0.0")
        #expect(inspected == 26)
        // 26 of a 30-page: the page did not fill its bound, so the claim is not
        // qualified.
        #expect(full == false)
    }

    /// The qualified miss. A page that filled its bound may simply not reach far
    /// enough back, and the surface must be able to say so.
    @Test("A page that filled its bound sets the page-was-full qualifier")
    func aPageThatFilledItsBoundSetsTheQualifier() async throws {
        let network = RecordingNetwork(queue: [
            .releases(try Fixture.data("GitHub/releases-page-full.json"))
        ])
        let store = store(network)

        store.load(packageID, version: "0.1.0", candidates: candidates)
        let state = await settled(store, packageID)

        guard case .loaded(.noReleaseMatchesVersion(_, _, let inspected, let full)) = state else {
            Issue.record("a full page settled as \(state)")
            return
        }
        // Against the source's injected bound, never against a literal.
        #expect(inspected == GitHubReleaseNotesSource.defaultPageSize)
        #expect(full, "a page that filled its bound reported an unqualified absence")
        #expect(network.requestCount == 1, "a full page triggered a second request")
    }

    // MARK: - Supersession and last-good survival

    @Test("A second load for the same package supersedes the first, and only the later lands")
    func aSecondLoadSupersedesTheFirst() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // Every request is answered with the same full page, so the two loads
        // are told apart by their **version** and not by the order the stubs
        // happen to be consumed in.
        let network = RecordingNetwork(fallback: try populatedPage())
        let store = store(network, cacheURL: url)

        // Two loads for two different versions, back to back, without awaiting
        // the first: the second must win.
        store.load(packageID, version: "1.18.0", candidates: candidates)
        #expect(store.state(for: packageID).isLoading)
        store.load(packageID, version: "1.19.0", candidates: candidates)
        let state = await settled(store, packageID)

        #expect(state.outcome?.release?.tagName == "v1.19.0", "the superseded load landed")
        // The superseded work was cancelled before it reached the wire, so the
        // second click did not cost a second request either.
        #expect(network.requestCount == 1, "supersession cost \(network.requestCount) requests")
    }

    @Test("A failed reload keeps the previous notes visible")
    func aFailedReloadKeepsThePreviousNotesVisible() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let network = RecordingNetwork(queue: [try populatedPage(), .transportFailure])
        let store = store(network, cacheURL: url)

        store.load(packageID, version: "1.18.0", candidates: candidates)
        _ = await settled(store, packageID)
        #expect(store.state(for: packageID).outcome?.release?.tagName == "v1.18.0")

        // A different version, so the cache cannot serve it, and the fetch fails.
        store.load(packageID, version: "1.19.0", candidates: candidates)
        let state = await settled(store, packageID)

        #expect(state.failure == .transport, "the failure was not surfaced")
        // Last-good survival: the note the user was reading is still there.
        #expect(
            state.lastGood?.release?.tagName == "v1.18.0",
            "a failed reload blanked a note already shown"
        )
    }

    @Test("Cancelling leaves the state at the last good value")
    func cancellingLeavesTheStateAtTheLastGoodValue() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let network = RecordingNetwork(queue: [try populatedPage()])
        let store = store(network, cacheURL: url)

        store.load(packageID, version: "1.18.0", candidates: candidates)
        _ = await settled(store, packageID)

        store.load(packageID, version: "1.19.0", candidates: candidates)
        store.cancel(packageID)
        await store.waitForLoad(packageID)

        #expect(
            store.state(for: packageID).lastGood?.release?.tagName == "v1.18.0",
            "cancelling lost the last good value"
        )
    }

    @Test("Two packages load independently and do not supersede each other")
    func twoPackagesLoadIndependently() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let network = RecordingNetwork(
            queue: [try populatedPage(), try populatedPage()],
            fallback: try populatedPage()
        )
        let store = store(network, cacheURL: url)
        let other = PackageID(kind: .cask, name: "vivid")

        store.load(packageID, version: "1.18.0", candidates: candidates)
        store.load(other, version: "1.19.0", candidates: candidates)
        _ = await settled(store, packageID)
        _ = await settled(store, other)

        #expect(store.state(for: packageID).outcome?.release?.tagName == "v1.18.0")
        #expect(store.state(for: other).outcome?.release?.tagName == "v1.19.0")
    }

    @Test("An untouched package is idle, not loading and not an absence")
    func anUntouchedPackageIsIdle() {
        let network = RecordingNetwork()
        let store = store(network)

        #expect(store.state(for: packageID) == .idle)
        #expect(store.states.isEmpty)
    }

    // MARK: - The budget reaches the surface

    /// Parsed from a **200** and published, so a sheet can warn before the wall
    /// and the optional token is something a user can see the point of.
    @Test("The rate-limit budget from a successful response reaches the store")
    func theBudgetFromASuccessfulResponseReachesTheStore() async throws {
        let network = RecordingNetwork(queue: [
            .releases(try Fixture.data("GitHub/releases-git-populated.json"), remaining: 12)
        ])
        let store = store(network)

        #expect(store.rateLimit == nil, "the store started with a budget it never asked for")

        store.load(packageID, version: "1.18.0", candidates: candidates)
        _ = await settled(store, packageID)

        let budget = try #require(store.rateLimit)
        #expect(budget.remaining == 12)
        #expect(budget.limit == 60)
        #expect(budget.isExhausted == false)
    }

    @Test("The budget from a rate-limit refusal also reaches the store, carrying its reset")
    func theBudgetFromARefusalAlsoReachesTheStore() async throws {
        let network = RecordingNetwork(queue: [.rateLimited()])
        let store = store(network)

        store.load(packageID, version: "1.18.0", candidates: candidates)
        _ = await settled(store, packageID)

        let budget = try #require(store.rateLimit)
        #expect(budget.isExhausted)
        #expect(budget.resetAt == Date(timeIntervalSince1970: 1_786_055_400))
    }

    // MARK: - The token

    @Test("A stored token is read once per load and authenticates the request")
    func aStoredTokenAuthenticatesTheRequest() async throws {
        let network = RecordingNetwork(queue: [try populatedPage()])
        let store = store(network, token: "ghp_storeUnderTest")

        store.load(packageID, version: "1.18.0", candidates: candidates)
        _ = await settled(store, packageID)

        let exchange = try #require(network.exchanges.first)
        #expect(exchange.headers["Authorization"] == "Bearer ghp_storeUnderTest")
    }

    // MARK: - Conditional revalidation

    /// A stale entry spends one request and no body. The cached answer is reused
    /// rather than refetched, which is the whole point of holding the validator.
    @Test("A stale entry revalidates with its ETag and a 304 reuses the cached answer")
    func aStaleEntryRevalidatesWithItsEtag() async throws {
        let url = cacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let network = RecordingNetwork(queue: [
            try populatedPage(),
            .notModified(etag: "\"page-1\"")
        ])
        let firstLoad = Date(timeIntervalSince1970: 1_786_000_000)

        // First load at T, second at T + 8 days: past the matched TTL.
        let early = store(network, cacheURL: url, now: firstLoad)
        early.load(packageID, version: "1.18.0", candidates: candidates)
        _ = await settled(early, packageID)

        let late = store(network, cacheURL: url, now: firstLoad.addingTimeInterval(8 * 86_400))
        late.load(packageID, version: "1.18.0", candidates: candidates)
        let state = await settled(late, packageID)

        #expect(network.requestCount == 2, "the stale entry was served without revalidating")
        #expect(
            network.exchanges.last?.headers["If-None-Match"] == "\"page-1\"",
            "the revalidation carried no validator"
        )
        #expect(
            state.outcome?.release?.tagName == "v1.18.0",
            "a 304 lost the cached answer instead of reusing it"
        )
    }
}
