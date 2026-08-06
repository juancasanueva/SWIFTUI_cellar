# Design: M5 Release Notes

Derived from `proposal.md` (decisions **D1–D6**, user-approved and binding) and probe **U5** (obs
7503). Slice 3 of 5; slices 1 and 2 archived. Written against the shipped code at `b3bd494` — every
seam named below was read, not assumed.

## Technical Approach

One new leaf target, `ReleaseNotes`, depending on **`Catalog` only**. Nothing depends back on it,
which is what makes the whole slice a `git revert` away and what keeps `Catalog` brew-free.

Five rules govern everything below.

1. **Consent is a compile-time gate, not a remembered call.** The one type that owns a `URLSession`
   accepts a `ReleaseNotesGrant`, and the only way to obtain one is `ReleaseNotesConsent.authorise()`.
   Unconsented egress is unrepresentable, then tested anyway.
2. **One sheet, one request, and no shape that could fan out.** The public fetch surface takes a
   single `PackageID`. There is no array overload, no batch method, no prefetch and no `.task`
   trigger. `OperationCenterBulk` never sees this target.
3. **Four absences are four values.** Unresolvable repo, repo with no releases, no release matching
   this version, and fetch failure — of which rate-limit exhaustion is its own case carrying its
   reset time. A 403 never renders as "no release notes".
4. **`CatalogPackage`, `CatalogSnapshot` and `currentSchemaVersion` are frozen.** This slice adds no
   field and spends none of slice 1's 2.4% footprint headroom. `CatalogFootprintTests` re-runs
   unchanged.
5. **The PAT is a secret; the grant is a preference.** Keychain and `UserDefaults` respectively —
   the same split `SecurityConsentPreference` / `KeychainAdvisoryCredentialStore` already ship.

## Architecture Decisions

| Choice | Rejected | Rationale |
|---|---|---|
| **`ReleaseNotes` re-declares consent + credential seams (D2)**: `ReleaseNotesConsent`, `ReleaseNotesConsentProviding`, `FixedReleaseNotesConsent`, `ReleaseNotesCredentialStoring`, `KeychainReleaseNotesCredentialStore` — identical rules to `ScanConsent`/`AdvisoryCredentialStoring`, service `com.juancasanueva.cellar.github-pat` | A `ReleaseNotes → SecurityKit` edge; a shared micro-target | D2, binding. `ScanConsent.authorise()` throws `AdvisoryError`, which lives in SecurityKit — importing it to reuse two structs would couple release notes to the CVE scanner. "No second consent mechanism" means no second set of *rules*, not no second code path. |
| **`authorise()` returns a `ReleaseNotesGrant` token** the network type requires, instead of returning `Void` | Mirroring `ScanConsent.authorise() -> Void` exactly | The one deliberate divergence from D2's shape, and a **strengthening** of the same rule: `ReleaseNotesGrant` has an `internal init` reachable only from `authorise()`, so "egress before a dated grant" stops being a discipline and becomes a type error. The rules — dated grant, revocation leaving no residue, throwing refusal, disclosure — are unchanged. |
| **Resolution over the *union* of four candidate URLs; `homepage → head → stable → cask url` is a tie-break only (U5)** | Naive homepage-first precedence | U5: homepage resolves 24.5% of installed formulae and 9.1% of casks; `urls.stable` resolves 54.7%. Fields disagreed on owner/repo **0 times** among installed, so precedence buys coverage, never correctness. A package resolvable only through `urls.stable` must still resolve. |
| **`GitHubRepository` is a failable value with a validated owner/name**; a malformed repo is unrepresentable | Carrying `owner`/`name` as free strings into a URL path | The `FormulaID`/`CaskID`/`MutationName.isSafe` discipline applied to a URL instead of argv: catalog text is attacker-influenceable and this is the one place it becomes a request path. |
| **One request to `/repos/{owner}/{repo}/releases?per_page=30`, matched locally** | `/repos/{owner}/{repo}/releases/tags/{tag}` | Decisive, not stylistic: the tag endpoint answers **404 for both** "this repo publishes no releases" and "no release matches this version", and rule 3 requires those to be different answers. The list endpoint distinguishes them in one request (`[]` versus a non-empty list with no matching tag). |
| **`data(for:)`, not `download(for:)`** | The catalog's file-based path | Release bodies are kilobytes; the 31 MB reasoning behind `CatalogSource`'s file discipline does not transfer. The byte-limit guard does, and is kept. |
| **Rate-limit headers are parsed from *every* response and surfaced to the store**, not only from 403 | Reading them only on refusal | The remaining budget is what lets the sheet warn *before* the wall, and D5's PAT field is only actionable if the user can see why they need it. |
| **`.unavailable` outcomes are never written to the cache** | Caching failures with a short TTL | D3, binding. A cached rate-limit refusal outlives the window it describes and turns a transient wall into a persistent lie. |
| **Two-tier TTL in the cache's own file** (`release-notes-cache.json`, 7 d matched / 24 h negative), own `ReleaseNotesSchema.currentVersion = 1` gated with the CS6 idiom | Reusing `CatalogSnapshot.currentSchemaVersion`; one uniform TTL | `AdvisoryCache` precedent. A separate version keeps an unrelated catalog field change from wiping the user's notes cache; the *gate idiom* is the requirement, sharing the constant is not. |
| **Cache entries carry the response `ETag`; a stale entry revalidates with `If-None-Match`** | Always refetching a full body once the TTL lapses | `HTTPCatalogSource`'s conditional-request discipline, applied where the scarce resource is 60 req/h rather than 31 MB. A 304 refreshes `storedAt` and spends one request instead of one request plus a body. |
| **Clock is an injected `now:`; every cache predicate is a pure function over it** | `Date()` inside the cache; a new date-provider protocol | Slice-2 precedent. `CatalogTimeSource` lives in `Catalog` and is a sync-engine concept; a `@Sendable () -> Date` matches `SecurityConsentPreference`'s existing shape and keeps TTL tests synchronous. |
| **Markdown degrades per block and never to an empty sheet** | Failing the sheet when `AttributedString(markdown:)` cannot parse | `AttributedString` supports CommonMark, not GFM: tables, task lists, `~~strikethrough~~`, bare autolinks and `@mentions` are not interpreted. Parsing block-by-block with `.returnPartiallyParsedIfPossible` means one unsupported construct costs its own paragraph's formatting, not the note. Total failure renders the raw body as monospaced text. |
| **Entry points are two explicit clicks (D4), and the outdated one does not go through `MutationMenu`** | Adding a "What's new?" item to `MutationMenu` | `MutationMenu` is the shared *mutation* surface driven by `OperationCenter`; a read-only, network-touching action in it would give every mutation call site an egress affordance. The item lives in `InstalledRow` beside it, gated on the row being outdated. |
| **App links the `ReleaseNotes` product explicitly in `cellar.xcodeproj`** | Assuming the transitive path that carried SecurityKit | Verified: the app imports `SecurityKit` today with **no** product link, because linked `Persistence` depends on it. `ReleaseNotes` has no such carrier — nothing depends on it, by design — so the link is structurally required, and this is the first target-membership edit since M4. |

## Interfaces

```swift
// Sources/ReleaseNotes/ReleaseNotesConsent.swift — D1/D2. Shape mirrors ScanConsent exactly.
public struct ReleaseNotesConsent: Sendable, Hashable, Codable {
    public let isGranted: Bool
    public let grantedAt: Date?                       // the two cannot disagree: no public init
    public static let notGranted: Self
    public static func granted(at: Date) -> Self
    public func revoked() -> Self                     // == .notGranted, no residue
    /// The only producer of a grant token. Throwing, never Bool: a refusal must be shown.
    @discardableResult public func authorise() throws(ReleaseNotesError) -> ReleaseNotesGrant
}
public struct ReleaseNotesGrant: Sendable { init() {} }   // internal init — unforgeable outside
public protocol ReleaseNotesConsentProviding: Sendable { func currentConsent() async -> ReleaseNotesConsent }
public struct FixedReleaseNotesConsent: ReleaseNotesConsentProviding { public init(_: ReleaseNotesConsent) }

// Sources/ReleaseNotes/ReleaseNotesCredentialStoring.swift — D5. Shape mirrors AdvisoryCredentialStoring.
public protocol ReleaseNotesCredentialStoring: Sendable {
    func personalAccessToken() async throws -> String?
    func store(personalAccessToken: String) async throws
    func removePersonalAccessToken() async throws
}
public struct KeychainReleaseNotesCredentialStore: ReleaseNotesCredentialStoring {
    public static let service = "com.juancasanueva.cellar.github-pat"   // distinct from the NVD item
    public static let accessibility = kSecAttrAccessibleAfterFirstUnlock as String
    public static var baseQuery: [String: Any] { /* generic password, service, synchronizable: false */ }
}

// Sources/ReleaseNotes/GitHubRepository.swift — resolution, pure and nonisolated.
public struct GitHubRepository: Sendable, Hashable, Codable {
    public let owner: String, name: String
    /// Fails on anything outside [A-Za-z0-9._-], on "." / "..", and on an empty component.
    public init?(owner: String, name: String)
}
public enum RepositorySource: String, Sendable, Hashable, Codable, CaseIterable {
    case homepage, headURL, stableURL, caskDownloadURL          // declaration order == tie-break order
}
public struct RepositoryCandidates: Sendable, Hashable {
    public let homepage, headURL, stableURL, caskDownloadURL: String?
    /// The one place this target reads a Catalog type. Reads URLs only — never a digest.
    public init(_ package: CatalogPackage)
}
public struct ResolvedRepository: Sendable, Hashable, Codable {
    public let repository: GitHubRepository
    public let source: RepositorySource                 // "every resolved repo names the URL that produced it"
    public let agreeingSourceCount: Int                 // U5 measured disagreement at 0; this makes it observable
}
public enum GitHubRepositoryResolver {
    public static func resolve(_ candidates: RepositoryCandidates) -> ResolvedRepository?
}

// Sources/ReleaseNotes/GitHubRelease.swift — Decodable only; nothing encodes a release.
public struct GitHubRelease: Sendable, Hashable, Codable {
    public let tagName: String, name: String?, body: String?
    public let isDraft: Bool, isPrerelease: Bool
    public let publishedAt: Date?, htmlURL: URL?
}
public enum GitHubReleaseDecoder {
    @concurrent
    public static func decode(_ data: Data) async throws -> [GitHubRelease]   // tolerant per element
}

// Sources/ReleaseNotes/ReleaseTagMatcher.swift — pure.
public enum ReleaseTagMatcher {
    /// Homebrew version strings are not upstream tags: a formula revision suffix (`2.43.0_1`)
    /// and a cask build suffix (`1.2.3,456`) are stripped before matching. Candidate tags are
    /// `x`, `vx`, `<name>-x`, `<name>_vx`, `release-x`, compared case-insensitively.
    public static func match(version: String, packageName: String, in: [GitHubRelease]) -> GitHubRelease?
}

// Sources/ReleaseNotes/ReleaseNotesOutcome.swift — one success, four absences (rule 3).
public struct RateLimitStatus: Sendable, Hashable, Codable {
    public let limit: Int?, remaining: Int?, resetAt: Date?
    public var isExhausted: Bool { remaining == 0 }
}
public enum ReleaseNotesFailure: Sendable, Hashable {
    case blockedPendingConsent
    case rateLimited(RateLimitStatus)      // 403/429 with an exhausted budget — never "not found"
    case unauthorized                      // 401: a rejected PAT must not read as a rate limit
    case httpStatus(Int), transport, payloadTooLarge, malformedPayload, cancelled
}
public enum ReleaseNotesOutcome: Sendable, Hashable {
    case notes(ResolvedRepository, GitHubRelease)
    case unresolvableRepository(triedSources: Set<RepositorySource>)
    case repositoryPublishesNoReleases(ResolvedRepository)
    case noReleaseMatchesVersion(ResolvedRepository, version: String, inspected: Int, pageWasFull: Bool)
    case unavailable(ReleaseNotesFailure)
    var isCacheable: Bool { if case .unavailable = self { false } else { true } }   // D3
}

// Sources/ReleaseNotes/ReleaseNotesSource.swift — the seam; the only URLSession in the target.
public protocol ReleaseNotesSource: Sendable {
    /// Singular by construction (rule 2): no `[PackageID]` overload exists anywhere in this target.
    func releases(
        for repository: GitHubRepository, validators: ConditionalValidators?,
        token: String?, grant: ReleaseNotesGrant
    ) async throws -> ReleaseFetchOutcome            // .notModified | .fetched([GitHubRelease], ETag?, RateLimitStatus)
}
public struct GitHubReleaseNotesSource: ReleaseNotesSource {
    public init(baseURL: URL = .gitHubAPI, byteLimit: Int = 2 * 1_048_576, perPage: Int = 30)
}

// Sources/ReleaseNotes/ReleaseNotesCache.swift — AdvisoryCache precedent.
public enum ReleaseNotesSchema { public static let currentVersion = 1 }
public struct ReleaseNotesCacheKey: Sendable, Hashable, Codable { let repository: GitHubRepository; let version: String }
public struct ReleaseNotesCacheEntry: Sendable, Hashable, Codable {
    public let outcome: ReleaseNotesOutcome, storedAt: Date, etag: String?
    public static let matchedTTL: TimeInterval = 7 * 86_400        // D3
    public static let negativeTTL: TimeInterval = 24 * 3_600       // D3
    public func isFresh(now: Date) -> Bool                          // tier chosen by the outcome case
}
public struct ReleaseNotesCacheFile: Sendable, Hashable, Codable {
    public static let entryLimit = 200
    public let schemaVersion: Int
    public let entries: [ReleaseNotesCacheKey: ReleaseNotesCacheEntry]
    public func pruned(now: Date) -> Self                           // expiry, then cap, oldest first
}
public actor ReleaseNotesCache { public init(fileURL: URL); func load() async -> ReleaseNotesCacheFile?; func save(_:) async throws }

// Sources/ReleaseNotes/ReleaseNoteRendering.swift — pure; Foundation only, no SwiftUI.
public struct RenderedReleaseNote: Sendable, Hashable {
    public let blocks: [AttributedString]
    /// Constructs this build showed as literal text rather than formatting.
    public let degradedConstructs: Set<UnsupportedMarkdown>   // .table, .taskList, .strikethrough, .mention, .bareAutolink
    public let renderedAsPlainText: Bool                      // total-parse-failure fallback
}
public enum ReleaseNoteRenderer {
    public static func render(_ body: String) -> RenderedReleaseNote
    /// http/https only, host non-empty — the `CaskInspection.browsableDownloadURL` allowlist, reused.
    public static func browsableLink(_ raw: String) -> URL?
}

// Sources/ReleaseNotes/ReleaseNotesStore.swift — shipped store shape.
@MainActor @Observable public final class ReleaseNotesStore {
    public private(set) var states: [PackageID: ReleaseNotesState] = [:]
    public private(set) var rateLimit: RateLimitStatus?
    /// One package. Called only from an explicit click. No array form, no `.task` caller.
    public func load(_ id: PackageID, version: String, candidates: RepositoryCandidates)
    public func cancel(_ id: PackageID)
}
public enum ReleaseNotesState: Sendable, Hashable { case idle, loading, loaded(ReleaseNotesOutcome) }
```

**The digest-key trap, stated where it bites.** A formula's digest is `urls.stable.checksum`; a
cask's is `sha256`. Slice 1 projected the formula **URLs only** and deliberately left
`urls.stable.checksum` out of scope, while `CaskInspection.declaredChecksum` carries the cask one
(including the `no_check` literal). `RepositoryCandidates` reads four **URL** fields and no digest
field of either name; the fixture README repeats this so nobody "fixes" a missing checksum later.

## Data Flow

```text
explicit click (outdated row action | package-detail section)   ← the ONLY triggers (D4)
        │
        ▼
ReleaseNotesStore.load(id:version:candidates:)         [@MainActor, per-id generation + Task]
        │
        ├── GitHubRepositoryResolver.resolve(candidates)   pure, union of 4 URLs, tie-break only
        │        └── nil ─────────────────────────▶ .unresolvableRepository   (cached 24 h)
        ▼
ReleaseNotesCache.load() ──▶ entry(for: key)?.isFresh(now:) ──▶ HIT: return, ZERO requests
        │ miss / stale
        ▼
consent.authorise() ──throws──▶ .unavailable(.blockedPendingConsent)  ← visible refusal, no request
        │ ReleaseNotesGrant
        ▼
credentials.personalAccessToken()          (Keychain; never held by the store, never logged)
        │
        ▼
GitHubReleaseNotesSource.releases(...)     ONE request. ephemeral · urlCache=nil ·
   GET api.github.com/repos/{o}/{r}/releases?per_page=30      reloadIgnoringLocalCacheData ·
   If-None-Match: <cached etag>                               byte-limit guard · data(for:)
        │
        ├── 304 ─────────▶ refresh storedAt, reuse cached outcome
        ├── 403/429 + remaining==0 ─▶ .rateLimited(reset)  ── NEVER cached, NEVER "not found"
        ├── 401 ─────────▶ .unauthorized                   ── a bad PAT is not a rate limit
        └── 200 ─▶ GitHubReleaseDecoder.decode [@concurrent] ─▶ ReleaseTagMatcher.match
                        │                       │
                        │ []                    ├─ hit ──▶ .notes           (cached 7 d)
                        └─▶ .repositoryPublishesNoReleases   └─ miss ─▶ .noReleaseMatchesVersion
                                                (both cached 24 h)          (cached 24 h)
        ▼
ReleaseNoteRenderer.render(body)  ─▶ ReleaseNotesSheet   no remote image · no auto-follow

bulk upgrade of N packages ──▶ OperationCenter fan-out ──▶ ZERO release-notes requests
                                (this target is not reachable from OperationCenterBulk)
```

## File Changes

| Files | Action |
|---|---|
| `Packages/CellarCore/Package.swift` | Modify — one `.library(name: "ReleaseNotes", …)`, one `.target(name:"ReleaseNotes", dependencies:["Catalog"], swiftSettings:[.swiftLanguageMode(.v6)])`, one `.testTarget` with `resources: [.copy("Fixtures")]`. **No existing target gains a dependency.** |
| `Sources/ReleaseNotes/ReleaseNotesConsent.swift`, `ReleaseNotesCredentialStoring.swift`, `ReleaseNotesError.swift` | Create — the two re-declared seams (D2) and the typed refusal. |
| `Sources/ReleaseNotes/GitHubRepository.swift`, `GitHubRepositoryResolver.swift` | Create — validated identity, union resolution, provenance. |
| `Sources/ReleaseNotes/GitHubRelease.swift`, `ReleaseTagMatcher.swift` | Create — tolerant decode, Homebrew-version normalisation, tag candidates. |
| `Sources/ReleaseNotes/ReleaseNotesOutcome.swift`, `RateLimitStatus.swift` | Create — the four absences and the header parse. |
| `Sources/ReleaseNotes/ReleaseNotesSource.swift` | Create — the seam and the **only** `URLSession` in the target. |
| `Sources/ReleaseNotes/ReleaseNotesCache.swift` | Create — schema gate, two-tier TTL, cap, actor. |
| `Sources/ReleaseNotes/ReleaseNoteRendering.swift` | Create — block-wise Markdown with typed degradation. |
| `Sources/ReleaseNotes/ReleaseNotesStore.swift` | Create — `@MainActor @Observable`, per-id cancellable work. |
| `Tests/ReleaseNotesTests/*.swift` + `Fixtures/GitHub/` | Create — see Testing Strategy. |
| `cellar/ReleaseNotes/ReleaseNotesSheet.swift`, `ReleaseNotesConsentSheet.swift`, `ReleaseNotesSection.swift`, `ReleaseNotesConsentPreference.swift` | Create — presentation + the app-owned grant. Under the `cellar` synchronized root: **no pbxproj source edit**. |
| `cellar/Installed/InstalledRow.swift` | Modify — one "What's new?" action beside `MutationMenu`, shown only when the row is outdated (D4 primary). |
| `cellar/Browse/PackageDetailView.swift` | Modify — one section, explicit button, shown only when a repo resolves (D4 secondary, D6). |
| `cellar/cellarApp.swift` | Modify — construct store, consent preference, Keychain store, cache URL; inject via `.environment`. |
| `cellar.xcodeproj/project.pbxproj` | Modify — **four objects**, enumerated in Rollback. |
| `cellarTests/ReleaseNotesCompositionTests.swift`, `cellarUITests/…` | Create — composition + E2E. |

## Concurrency and Isolation

- Every new public value type is a struct/enum over `String`/`Int`/`Date`/`URL`/`Set`/arrays and
  declares `Sendable` **explicitly**, per project convention. `AttributedString` is `Sendable`, so
  `RenderedReleaseNote` crosses domains freely.
- `GitHubRepositoryResolver`, `ReleaseTagMatcher`, `ReleaseNoteRenderer` are `enum` namespaces of
  `nonisolated static` pure functions — no actor, no `await`, synchronously testable (slice-1 lesson).
- `GitHubReleaseDecoder.decode` is `@concurrent` **on its own line, before `public static func`**
  (the other order does not compile; recorded as having cost an apply cycle in M1).
- `ReleaseNotesCache` is an `actor` (`AdvisoryCache` precedent) holding an injected `fileURL`; writes
  are atomic with `.sortedKeys`, so a crash mid-write leaves the previous file intact.
- `GitHubReleaseNotesSource` is a `Sendable` struct owning one `URLSession` built from
  `URLSessionConfiguration.ephemeral` with `urlCache = nil`.
- `ReleaseNotesStore` is `@MainActor @Observable` with `@ObservationIgnored` internals, `private(set)`
  state, a per-`PackageID` generation counter and `Task` map (`CleanupStore`/`SecurityStore` shape),
  cancel-on-supersede, and last-good survival: a failed reload never blanks a note already shown.
- Cancellation is honoured — `Task.checkCancellation()` before the request and before the decode;
  `.cancelled` is a `ReleaseNotesFailure`, never an error dialog.
- `ReleaseNotesConsentPreference` is `@MainActor @Observable` in the **app** target and owns the
  `UserDefaults` keys. `ReleaseNotes` holds no `UserDefaults` and no `@AppStorage` — asserted
  structurally, exactly as `CredentialStoreTests` does for SecurityKit.
- No `@unchecked Sendable`, no `nonisolated(unsafe)`, no `#available`.

## Testing Strategy

Strict TDD, RED before GREEN. `swift test --package-path Packages/CellarCore` is the inner loop; the
composition and E2E cases run under `xcodebuild`.

| # | Layer | What / how |
|---|---|---|
| 1 | Unit — resolution | Each of the four fields **alone** resolves (U5's `urls.stable`-only case is explicit). Union: a package with only `urls.stable` resolves; `agreeingSourceCount` is exact. Tie-break order is asserted against a record where all four agree. Non-GitHub hosts (gnu.org, python.org, videolan.org) resolve to `nil`, not to a guess. `.git` suffix stripped; `/releases/download/…` and `/archive/refs/tags/…` paths yield the same repo. |
| 2 | Unit — repository validity | `GitHubRepository.init?` refuses `..`, empty components, path traversal, percent-encoding, whitespace, and a reserved first segment. A refused candidate falls through to the next source rather than failing resolution. |
| 3 | Unit — tag matching | `2.43.0_1` matches tag `v2.43.0` (formula revision stripped); `1.2.3,456` matches `1.2.3` (cask build stripped); `<name>-x` and `release-x` forms; case-insensitive; a draft release never matches; a prerelease matches only on an exact tag. No match over a non-empty list yields `.noReleaseMatchesVersion`, never `.repositoryPublishesNoReleases`. |
| 4 | Unit — outcomes | All five cases are reachable and distinct. `[]` ⇒ `.repositoryPublishesNoReleases`. 403 + `x-ratelimit-remaining: 0` ⇒ `.rateLimited` carrying `resetAt`, **not** `.httpStatus(403)` and **not** an absence. 401 ⇒ `.unauthorized`. A full page with no match sets `pageWasFull`. |
| 5 | Unit — rate-limit headers | Parsed from a 200 as well as a 403; missing headers give `nil` fields, never `0`; `reset` epoch seconds decode to a `Date`; `RateLimitStatus` reaches the store on the success path. |
| 6 | Unit — consent gate | `.notGranted` ⇒ `authorise()` throws and no `ReleaseNotesGrant` exists; a recording transport observes **zero** requests. A revoked grant leaves no residue. `ReleaseNotesGrant` has no public initialiser (public-surface enumeration, `IntegrityProhibitionTests` idiom). |
| 7 | Unit — cache | Missing, corrupt and version-mismatched files each read as **absent**, and a recording file seam proves a read wrote and removed nothing. Matched entry fresh at 6 d 23 h, stale at 7 d 1 h; negative entry fresh at 23 h, stale at 25 h — with an injected `now`. `.unavailable` is **never** persisted (D3). Cap of 200 drops the oldest first; pruning is idempotent. Key is `(repository, version)`: two versions of one repo are two entries. |
| 8 | Unit — conditional request | A stale entry with an ETag sends `If-None-Match`; a 304 refreshes `storedAt`, reuses the cached outcome, and issues no decode. An entry without an ETag sends no header. |
| 9 | Unit — byte limit | A response over the limit is refused as `.payloadTooLarge` and nothing is decoded or cached; `expectedContentLength` over the limit refuses before the body is read. |
| 10 | Unit — Markdown | A GFM table, a task list, `~~strikethrough~~`, an `@mention` and a bare autolink each render as readable literal text and are reported in `degradedConstructs`. A body that fails entirely renders as plain text with `renderedAsPlainText`. An image reference produces **no** URL a view could fetch. `browsableLink` refuses `javascript:`, `file:`, `data:` and a host-less URL. An empty body is an empty render, never a crash. |
| 11 | Unit — store | Per-package generation: a second `load` for the same id cancels the first and only the later result lands. A failed reload keeps the previous `.notes` visible (last-good survival). `cancel` leaves state at the last good value. |
| 12 | Structural — zero egress without consent | Two guards. (a) Recording transport: 30 outdated packages submitted through `OperationCenterBulk.submitUpgrades` issue **zero** release-notes requests, and `ReleaseNotesStore` is never touched. (b) Source scan of `Sources/ReleaseNotes/`: `URLSession`/`URLRequest` appear in exactly one file, that file's fetch entry point requires a `ReleaseNotesGrant`, and the target contains no `[PackageID]`/`submitBulk`/`prefetch` symbol. Comments stripped first, per the shipped `SecurityCompositionSupport` idiom. |
| 13 | Structural — secret containment | `Sources/ReleaseNotes/` contains no `UserDefaults`, no `@AppStorage`, no `print`/`NSLog`/`os_log` on any token path. `KeychainReleaseNotesCredentialStore.baseQuery` asserts generic password, the **distinct** service name, `synchronizable: false`, and `kSecAttrAccessibleAfterFirstUnlock`; its service name is asserted **different** from `KeychainAdvisoryCredentialStore.service`. Keychain calls themselves are untested, for the shipped reason. |
| 14 | Regression — footprint | `CatalogFootprintTests` runs **unchanged** and passes; a structural scan asserts `CatalogPackage`'s stored-property set and `currentSchemaVersion` are unchanged. |
| 15 | Integration — one request per sheet | A single `load` issues exactly one request; an immediate second `load` for the same key issues **zero**. Resolution failure issues zero. Consent refusal issues zero. |
| 16 | App target | The `ReleaseNotes` module is importable from the app (proves the product link reached the target — this is the pbxproj edit's test); the release-notes consent sheet names `api.github.com` and states what is disclosed; the disclosure text is a named constant, not a body literal (`SecurityConsentSheet` precedent). |
| 17 | E2E (XCUITest) | Without a grant, the outdated row's "What's new?" shows the consent surface, not a spinner and not an empty sheet. With a grant and a stubbed transport, a note renders. A rate-limited response shows the reset time and the PAT affordance — and does **not** read as "no release notes". |

**Fixture plan** — `Tests/ReleaseNotesTests/Fixtures/GitHub/`, to the `Fixtures/Cleanup` standard:
`README.md` recording capture date, the exact request (method, URL, headers sent, `per_page`), the
HTTP status and **the response headers verbatim** (the rate-limit headers are load-bearing, so this
standard adds a `*.headers.txt` beside each body); `probe-manifest.txt`; SHA-256 per stream. Bodies:
`releases-git-populated.json`, `releases-empty.json`, `releases-no-matching-tag.json`,
`release-body-gfm.json` (table + task list + mention + bare autolink + image), `error-403-ratelimit`,
`error-401-unauthorized`, `error-404-repo`. Every fixture is captured from `api.github.com`
unauthenticated — no PAT is ever recorded into the repository.

## Threat Matrix

| Boundary | Applicability | Response / RED |
|---|---|---|
| Network egress to a new host | **Applicable** | First `api.github.com` egress. Consent is a compile-time gate plus a dated grant; one request per sheet; no prefetch, no fan-out, no `.task` trigger. RED: 6, 12, 15. |
| Rate-limit exhaustion as a denial surface | **Applicable** | Typed, never cached, never a retry trigger, never rendered as absence; headers surfaced on every response. RED: 4, 5, 7, 17. |
| Untrusted remote content into the UI | **Applicable** | Release bodies are attacker-authored. No remote image is fetched, no link is followed automatically, links pass the http/https allowlist reused from `CaskInspection.browsableDownloadURL`, unparsable Markdown degrades to text. RED: 10. |
| Attacker-influenceable catalog text into a URL path | **Applicable** | `GitHubRepository.init?` validates owner/name; a malformed repo is unrepresentable, mirroring `FormulaID`/`CaskID`. RED: 2. |
| Untrusted on-disk input | **Applicable** | The cache file is writable by any local process: exact schema gate, `try?` throughout, entry cap bounds size, a failed decode degrades to "cached nothing" (which costs one request, never a wrong answer). RED: 7. |
| Credential storage | **Applicable** | Keychain only, distinct service name, `synchronizable: false`, after-first-unlock, never echoed back into the field, never logged. RED: 13. |
| Unbounded response size | **Applicable** | Byte-limit guard on both `expectedContentLength` and the received body. RED: 9. |
| Routing, shell commands, subprocesses, VCS/PR automation, executable-file classification, process integration | N/A — no such boundary | This slice invokes no `brew`, spawns no process, and touches no argv. Asserted by the target graph: `ReleaseNotes` cannot see `BrewProcess`. |

## Migration / Rollout

**No migration.** `CatalogPackage`, `CatalogSnapshot`, `CatalogState` and `currentSchemaVersion` are
untouched, so no cache is invalidated and no re-download occurs. `release-notes-cache.json` is
created on first use and carries its own schema version.

**Rollback** (binding, from the proposal, with the pbxproj list made exact):

1. **`Package.swift`** — remove one `.library`, one `.target`, one `.testTarget`, plus
   `Sources/ReleaseNotes/` and `Tests/ReleaseNotesTests/`. No existing target depends on
   `ReleaseNotes`, so removal cannot break `Catalog`/`BrewClient`/`SecurityKit`/`Persistence`.
   Check: `swift build --package-path Packages/CellarCore`.
2. **`cellar.xcodeproj/project.pbxproj`** — remove exactly **four** objects, and nothing else:
   (a) the `PBXBuildFile` entry `ReleaseNotes in Frameworks`; (b) its line in the `cellar` target's
   `PBXFrameworksBuildPhase` `files` list; (c) its line in the target's `packageProductDependencies`;
   (d) the `XCSwiftPackageProductDependency` object `productName = ReleaseNotes`. Follow the shipped
   `BC00000100000000000000NN` identifier convention. **No** build setting, scheme, signing or
   synchronized-group change. New app sources under `cellar/` need no pbxproj edit (`cellar` is a
   `PBXFileSystemSynchronizedRootGroup`, confirmed in slices 1–2). Check:
   `xcodebuild build -scheme cellar`.
3. **User state** — the cache file is orphaned and inert after revert and is re-adopted intact on
   re-apply, because it carries its own schema version. No catalog cache is invalidated. **A stored
   PAT survives a revert with nothing left to read it: remove it from the consent surface *before*
   reverting.** The consent grant survives as two `UserDefaults` keys, likewise inert.

   **The order is not optional, and it is the first step of any revert of this change.** The exact
   sequence: open the release-notes consent surface (the "What's new?" action on any outdated row,
   or the Release notes section on a package detail page) → press **Remove** beside the token field
   → confirm the status line reads "No token stored" → *then* revert. After the revert, the
   Keychain item `com.juancasanueva.cellar.github-pat` still exists and nothing in the app can read
   or delete it; clearing it would mean Keychain Access and a user who knows the item's name. The
   grant's two defaults keys (`releaseNotes.consentGranted`, `releaseNotes.consentGrantedAt`) are
   harmless if left behind — they are inert with no code to read them, and are re-adopted correctly
   on re-apply — but the credential is not.

## Apply-Time Amendments

Every change evidence forced during apply, recorded rather than absorbed. Nothing
in D1–D6 moved; each item below is a *how*, and each one is here because a
reviewer reading the design above would otherwise find the code disagreeing with
it.

1. **`bytes(for:)`, not `data(for:)`.** Task 6.4 requires refusing an oversized
   response *before the body is read*, and `data(for:)` cannot: it returns only
   after the whole body has arrived, so the earliest possible check is before the
   **decode**. `bytes(for:)` hands back the response first, so
   `expectedContentLength` is judged before a byte is consumed, and the
   accumulation loop bounds what actually arrives when the declared length lies or
   is absent. The design's rejection of `download(for:)` and its file discipline
   stands unchanged — this is still an in-memory read of a kilobytes-sized body.

2. **`GitHubReleaseNotesSource.baseURL` is a `String` constant**, not
   `URL.gitHubAPI`. It matches the shipped `NVDSource.baseURL` / `OSVSource.baseURL`
   idiom, which is what the exact-set host guard in
   `ReleaseNotesEgressStructureTests` compares its scanned literals against.

3. **`session:` is a constructor parameter** on `GitHubReleaseNotesSource`. The
   Interfaces block omitted it; the design's own Testing Strategy requires a
   recording `URLProtocol` transport, which needs session injection. Same shape as
   the shipped `NVDSource(session:credentials:byteLimit:)`.

4. **`ReleaseNotesFailure` conforms to `Error`.** It has to, to be usable as a
   *typed* thrown type on the acquisition seam. It remains a value first: the store
   turns each case into `.unavailable(_)` and renders it, and nothing catches one
   into a dialog.

5. **`UnsupportedMarkdown` gained a `.image` case.** The design listed five
   constructs; an image reference is a sixth thing that degrades, and it degrades
   for a *containment* reason rather than a rendering one. Telling the reader an
   image was there and was not fetched is more honest than silently dropping it.

6. **The renderer strips links the allowlist refuses.** Found by a RED test, not
   assumed: `AttributedString(markdown:)` parses `[click](javascript:alert(1))` and
   attaches the destination as a `.link`, which SwiftUI's `Text` hands to the
   workspace opener. The check cannot live at the view — a second view rendering
   the same value would have to remember it — so `ReleaseNoteRenderer` removes the
   attribute and keeps the text.

7. **Cache entries are encoded as a sorted array of records.** `Codable` writes a
   dictionary with a non-`String` key as an unkeyed array in iteration order, which
   is not stable between runs, so two saves of identical content would produce
   different bytes and the atomic write would be replacing a file with a shuffled
   copy of itself.

8. **The cache's filesystem access is a named seam** (`ReleaseNotesFileAccess`).
   The requirement that a rejecting read "wrote, replaced and removed nothing" is
   an absence, and an absence is only provable if something counted the presences.

9. **Fixture projection.** Three captured release pages are 0.3–0.9 MB each,
   almost all of it `assets`, `author` and `*_url` fields nothing decodes. They ship
   projected to the seven decoded keys — values byte-identical, no element dropped
   or reordered — and `Fixtures/GitHub/README.md` records the SHA-256 of each
   original capture so the projection is auditable. Two streams are **authored**
   rather than captured, and say so: `error-403-ratelimit` (capturing a real one
   means exhausting a shared IP's hourly budget) and the two `release-body-*.json`
   corpora (no real release carries all six GFM constructs at once).

10. **Recorded placements (from `tasks.md` 10.2 / 10.5), now shipped.** The
    bulk-egress guard and the service-name distinctness assertion live in
    `cellarTests/ReleaseNotesEgressCompositionTests.swift`, because `ReleaseNotes`
    sees neither `BrewClient` nor `SecurityKit` and the app test target is the only
    place that sees all three.

11. **The bulk guard uses a per-instance recorder**, not the shipped
    process-global `CompositionRequestSpy`. Swift Testing runs suites concurrently,
    so a test that *makes* a request to prove a global counter works clobbers a
    concurrent test asserting that counter is zero — observed, in alternation,
    before `CompositionNetwork` existed. The control now lives inside the same test,
    over the same store and transport.

12. **The ambient-trigger guard is narrowed to the path that can reach the
    network.** A blanket ban on `.task` would be wrong: `ReleaseNotesConsentSheet`
    uses one to read the Keychain for its own status line. The shipped claim is
    stronger and more precise — `store.load` is called from exactly one file, and
    that file contains no ambient trigger at all.

13. **The runtime half of "no brew process" is stated as an effect enumeration.**
    The design asks for a recording process seam; there is none to inject, because
    `ReleaseNotes` depends on `Catalog` alone and no process API is in its module
    graph. So `theWholeFlowProducesExactlyTwoKindsOfEffect` runs resolve → fetch →
    match → cache → read back and asserts the *complete* set of external effects is
    one HTTP request to the one compiled-in host plus this capability's own cache
    file. A spawned process would have to arrive through an effect that list does
    not contain.

14. **`InstalledRow` falls back to the snapshot's own `homepage`** when a package
    has no catalog record. This widens coverage, not the rule: `brew info` publishes
    the same field the catalog dump does, resolution still runs over published URLs
    only, and a homepage that is not a GitHub repository still resolves to nothing.
    It follows the row's existing discipline for `desc` — the snapshot is the source
    that exists even with a cold or third-party-tap catalog (installed-inventory
    II7).

15. **Open Question 1 is resolved.** `per_page` stays **30** as the shipped
    default. It is a *parameter* (`GitHubReleaseNotesSource(perPage:)`), every
    page-boundary test asserts against the injected bound, `pageWasFull` carries the
    honesty, and exactly one test names the number so a change to it is visible
    rather than silent.

16. **Five `nonisolated(unsafe)` declarations ship, all in `ReleaseNoteRendering.swift`.** The
    Concurrency section above says "no `nonisolated(unsafe)`", and that is now inaccurate. Each one
    is a `private static let` holding a compiled `NSRegularExpression`: immutable after
    initialisation, and `NSRegularExpression` is documented as thread-safe for matching. The
    annotation is required only because the type is not `Sendable`, and the alternatives are worse —
    recompiling five patterns on every `render` call, or wrapping thread-safe immutable values in a
    lock that exists to satisfy the compiler rather than to protect anything. The optionals are an
    artefact of the throwing initialiser; a `nil` degrades that construct to "reported nothing"
    rather than crashing. **No `@unchecked Sendable` and no `#available` ship**, as stated.

17. **The `GlobalRequestSpy` process-global counter was removed (remediation).** It counted into a
    `static var` behind an `NSLock` and was **reset by `install()`**, so a concurrently-starting
    sibling suite could wipe a request another suite had already recorded — an egress guard able to
    report a **false zero**, which is the one failure mode a guard must not have. Six tests across
    five concurrent suites triangulated through it and
    `theWholeFlowProducesExactlyTwoKindsOfEffect` failed 6/6 parallel runs. Every site now uses the
    per-instance, tagged `RecordingNetwork` — the same shape `cellarTests` already needed for the
    same reason (item 11) — so counts cannot cross-contaminate in either direction. Two claims were
    *strengthened* rather than merely ported: the consent test's control is now the shipped source on
    the same transport reached through a real grant, and the flow test's "nothing reached another
    session" is now stated where it belongs, as the structural guard that proves no other session
    exists.

18. **XCUITest execution is blocked in this environment.** The four E2E cases in
    `cellarUITests/ReleaseNotesUITests.swift` are written and compile, and they
    could not be *run*: the pre-existing `DiskUsage`/`Discover` UI suites fail the
    same way on a clean checkout of `main` with this change stashed — the app
    launches but its accessibility tree is unreachable to the runner. Recorded as an
    infrastructure blocker, not as a result.

## Open Questions

- [ ] **`per_page=30` is a judgment, not a decision from D1–D6.** It bounds one response and covers
      the primary (newest-version) entry point completely. For an old installed version on a
      fast-releasing repo the match can fall off the page; `pageWasFull` keeps that honest in the
      copy ("not among the 30 most recent releases"), but if it proves common the honest fix is a
      larger page, never a second request.
- [ ] **Consent-surface copy** must name what a repo name discloses (that this Mac has this package
      and is about to upgrade it), per D1. The wording is authored at apply time against the
      `SecurityConsentSheet` constants pattern and is worth a read-through.

*Size note: this document exceeds the 800-word skill budget, as every design in this project does.
The project convention — a design dense enough that apply needs no re-derivation — wins.*
