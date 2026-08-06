# Tasks: M5 Release Notes

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | **3,700–4,700** authored source+tests (~1,300 CellarCore source, ~1,700–2,000 CellarCore tests, ~350–450 fixtures + README/manifest, ~550 app, ~200 `cellarTests`, ~120 `cellarUITests`, 4 pbxproj lines) |
| Session review budget | **5,000** lines (session override of `config.yaml`'s 2,000) |
| 5,000-line budget risk | Medium–High — the range's top edge grazes the budget once lifecycle markdown is counted |
| 2,000-line budget risk | High |
| 400-line budget risk | High |
| Chained PRs recommended | Yes (conditional — see below) |
| Suggested split | PR 1 = Phases 1–10 (the whole CellarCore capability); PR 2 = Phases 11–12 (pbxproj link + app layer + E2E) |
| Delivery strategy | single-pr |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

Resolution of the budget lines: `400-line budget risk: High` is the mandatory default-budget guard
line and is honestly High — the forecast exceeds 400 by an order of magnitude. The budget governing
this session is **5,000**. Unlike slice 2 (2,000–2,900, comfortably inside), this slice's honest
range reaches **4,700 authored** and the design closed with **17** RED-first test layers plus a
sidecar-per-response fixture standard; adding this change's lifecycle markdown can cross 5,000. That
is a real fork, so it is a decision and not an assumption:

- **Option A — single PR with `size:exception`.** Honours `delivery_strategy: single-pr`. The
  capability lands whole; the pbxproj link is verified in the same PR that adds the target.
- **Option B — two PRs, feature-branch-chain.** PR 1 base = the feature/tracker branch, PR 2 base =
  PR 1 branch. PR 1 already satisfies all nine `release-notes` requirements at the CellarCore level
  and is fully proven by `FAST`; PR 2 carries the only pbxproj edit and the app surfaces.

The split is pre-agreed either way: if the real diff crosses 5,000 mid-apply, cut at **Phase 11**.
Nothing in Phases 1–10 depends on it, and no requirement in the delta spec is app-side (D4 is
carried by tasks, not by a requirement).

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | CellarCore `ReleaseNotes` target: fixtures, resolution, consent + Keychain seams, wire + tag matching, five outcomes, rate-limit headers, the one-request source, the two-tier cache, Markdown degradation, the store, the structural guards (Phases 1–10) | PR 1 | `FAST --filter "GitHubRepository\|GitHubRepositoryResolver\|ReleaseNotesConsent\|ReleaseNotesCredential\|GitHubReleaseDecoder\|ReleaseTagMatcher\|ReleaseNotesOutcome\|RateLimitStatus\|GitHubReleaseNotesSource\|ReleaseNotesCache\|ReleaseNoteRendering\|ReleaseNotesStore\|ReleaseNotesEgress\|ReleaseNotesFixtureManifest\|CatalogFootprint"` | N/A for a UI run — nothing links this target yet. Runtime proof is the fixture capture in 1.2 replayed: `swift test` with the recorded `Fixtures/GitHub/` bodies + `*.headers.txt` must reproduce all five outcomes offline | `git revert` the merge; `Package.swift` loses one `.library`, one `.target`, one `.testTarget`; `Sources/ReleaseNotes/` and `Tests/ReleaseNotesTests/` are removed. No existing target gains a dependency, so nothing else can break |
| 2 | pbxproj product link, app surfaces (consent sheet + PAT field, notes sheet, both entry points, wiring), composition + E2E (Phases 11–12) | PR 1 (or PR 2 if cut) | `APP --only-testing:cellarTests/ReleaseNotesCompositionTests` then `FULL` | Launch: an outdated row's "What's new?" with no grant shows the consent surface (not a spinner); grant, then a stubbed rate-limited response shows the reset time and the PAT affordance and does **not** read as "no release notes" | Delete `cellar/ReleaseNotes/`, revert the two modified app files and `cellarApp.swift`, and remove the **four** pbxproj objects enumerated in 11.1. A stored PAT must be removed from the consent surface **before** reverting |

If cut, PR 2 base = PR 1 branch (feature-branch-chain).

### Legend

- Paths under `Packages/CellarCore/` unless prefixed with `cellar/`, `cellarTests/`, `cellarUITests/` or `openspec/`.
- `FAST` = `swift test --package-path Packages/CellarCore` (optionally `--filter <Suite>`).
- `APP` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.
- `FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.
- `BUILD` = `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.
- Spec tags — `release-notes` (ADDED-only, 9 req / 39 sc): **RN-R1** union resolution never a guess, **RN-R2** nothing leaves before a dated grant, **RN-R3** one request per opened request / bulk issues none, **RN-R4** four absences are four values and a rate-limit refusal is none of them, **RN-R5** deterministic tag matching, **RN-R6** two-tier TTL cache, **RN-R7** the token is a Keychain secret and optional, **RN-R8** a body renders without failure, **RN-R9** no brew process and no catalog change.
- Design test-layer tags **T1**–**T17** (`design.md` → Testing Strategy). Threat-matrix tags — **TM1** new-host egress, **TM2** rate-limit exhaustion as denial, **TM3** untrusted remote content into the UI, **TM4** attacker-influenceable catalog text into a URL path, **TM5** untrusted on-disk input, **TM6** credential storage, **TM7** unbounded response size. Routing, shell, subprocess, VCS/PR automation, executable-file classification and process integration are `N/A` and have no task.
- **No Phase 0.** Nothing is widened: `CatalogPackage`, `CatalogSnapshot` and `currentSchemaVersion` are frozen, so the only regression gate is re-running `CatalogFootprintTests` **unchanged** (task 10.3) with a zero-line diff. No baseline capture is needed.
- Strict TDD: every `RED` task lands a failing test; the following `GREEN` task makes it pass. No production line without a red test.
- Binding: `@concurrent` goes on its **own line before** `public static func` on `GitHubReleaseDecoder.decode` — the other order does not compile and cost an apply cycle in M1.
- Binding: `per_page` is a **parameter** (`GitHubReleaseNotesSource(perPage:)`), not a literal in the tests. Every page-boundary assertion compares against the injected bound ("the page filled its bound"), never against a hardcoded `30`. `30` is a judgment recorded in design's first Open Question, not a decision from D1–D6.
- Binding: `ReleaseNotesGrant`'s `init` is **internal**. Unconsented egress must be a compile error first and a test second.
- Binding: `ReleaseNotes` depends on **`Catalog` only**. Two consequences carried below as recorded placements, not silent absorptions: the bulk-egress guard (T12a) and the service-name-distinctness assertion (T13, cross-module half) live in `cellarTests`, the only place that sees both `BrewClient`/`SecurityKit` and `ReleaseNotes`.

---

## Phase 1: Target scaffolding and fixtures (test data + build graph, no behaviour)

- [x] 1.1 `Packages/CellarCore/Package.swift`: add one `.library(name: "ReleaseNotes", targets: ["ReleaseNotes"])`, one `.target(name: "ReleaseNotes", dependencies: ["Catalog"], swiftSettings: [.swiftLanguageMode(.v6)])`, and one `.testTarget(name: "ReleaseNotesTests", dependencies: ["ReleaseNotes", "CellarTestSupport"], resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v6)])`. **No existing target gains a dependency.** Check: `swift build --package-path Packages/CellarCore`.
- [x] 1.2 Capture `Tests/ReleaseNotesTests/Fixtures/GitHub/` from `api.github.com` **unauthenticated** — no PAT is ever recorded into the repository. Bodies: `releases-git-populated.json`, `releases-empty.json`, `releases-no-matching-tag.json`, `releases-page-full.json` (a page that filled its bound, all newer than the target version — **RN-R4** *A version past the page bound is a qualified miss*), `release-body-gfm.json` (table + task list + `@mention` + `~~strikethrough~~` + bare autolink + image reference), `release-body-malformed.json`, `error-403-ratelimit`, `error-401-unauthorized`, `error-404-repo`. Each body gets a sibling `*.headers.txt` with the response headers **verbatim** — the rate-limit headers are load-bearing.
- [x] 1.3 `Fixtures/GitHub/README.md` to the `Tests/BrewClientTests/Fixtures/Cleanup` standard: capture date, exact request (method, URL, headers sent, the `per_page` used), HTTP status, verbatim response headers, and the provenance of every stream; plus `probe-manifest.txt` with a SHA-256 per stream. Record the **digest-key trap** here: `RepositoryCandidates` reads four *URL* fields and no digest field — a formula's digest is `urls.stable.checksum` (out of scope since slice 1) and a cask's is `sha256` → `CaskInspection.declaredChecksum`; nobody should later "fix" a missing checksum.
- [x] 1.4 RED create `Tests/ReleaseNotesTests/FixtureLoading.swift` and `ReleaseNotesFixtureManifestTests.swift` (`SecurityKitTests/FixtureManifestTests` idiom): every stream named in `probe-manifest.txt` exists, loads from `Bundle.module`, and hashes to the recorded SHA-256. A silently re-saved fixture must fail the suite.

## Phase 2: Repository identity and union resolution (**RN-R1**, **D6**, **TM4**, T1, T2)

- [x] 2.1 RED create `Tests/ReleaseNotesTests/GitHubRepositoryTests.swift` (**TM4**, T2): `GitHubRepository.init?` refuses `.`/`..`, an empty component, path traversal, percent-encoding, whitespace, characters outside `[A-Za-z0-9._-]`, and GitHub's reserved first segments; it accepts a legal `owner/name`. A malformed repository is unrepresentable — the `FormulaID`/`CaskID`/`MutationName.isSafe` discipline applied to a URL path.
- [x] 2.2 GREEN create `Sources/ReleaseNotes/GitHubRepository.swift`: failable `init?(owner:name:)`, `Sendable, Hashable, Codable`.
- [x] 2.3 RED create `Tests/ReleaseNotesTests/GitHubRepositoryResolverTests.swift`, the union rule: a formula whose `homepage` is `https://gnu.org/software/foo` and whose only `formulaSources.stableURL` is a GitHub archive tarball still resolves to `acme/foo`, credited to `stableURL` (**RN-R1** *A package resolvable only via `urls.stable` still resolves*); a cask resolves from `caskInspection.downloadURL` (*A cask resolves from its download URL*). A non-yielding field must never block another.
- [x] 2.4 RED same file, tie-break and provenance: all four fields yielding `acme/foo` credits `homepage` and reports `agreeingSourceCount == 4`; removing `homepage` alone still resolves, credited to `headURL` (**RN-R1** *The tie-break decides only which field is credited*). Assert the tie-break never short-circuits evaluation — a refused candidate falls through to the next source instead of failing resolution (T2).
- [x] 2.5 RED same file, host and shape rules: `gist.github.com`, `raw.githubusercontent.com`, `*.github.io`, `gitlab.com`, `codeberg.org` all report the typed unresolvable value with no partial `owner/repo` (**RN-R1** *Non-repository and non-GitHub hosts never resolve*); `https://www.github.com/Acme/Foo.git`, `https://github.com/Acme/Foo/` and `https://github.com/Acme/Foo/releases/tag/v1.0?utm=x#top` produce one identity carrying no `.git`, slash, query or fragment (*Ornamented URLs normalize to one identity*).
- [x] 2.6 RED same file (**TM1**): with a recording network seam, an all-absent/non-GitHub package reports the typed unresolvable value, throws nothing, settles as the no-repository-resolved outcome **naming the sources tried**, distinct from "publishes no releases", and the recorder saw **no request** (**RN-R1** *Unresolvable is a typed answer, and costs nothing*).
- [x] 2.7 GREEN create `Sources/ReleaseNotes/GitHubRepositoryResolver.swift` with `RepositorySource` (declaration order == tie-break order), `RepositoryCandidates(_ package: CatalogPackage)` — **the one place this target reads a Catalog type, four URL fields and no digest** — `ResolvedRepository { repository, source, agreeingSourceCount }`, and a `nonisolated static` pure `resolve`. No request, no `brew`, no cache read, no search or name-similarity step.

## Phase 3: Consent gate and the Keychain token (**RN-R2**, **RN-R7**, **D1**/**D2**/**D5**, **TM6**, T6, T13)

- [x] 3.1 RED create `Tests/ReleaseNotesTests/ReleaseNotesConsentTests.swift`: `.notGranted.authorise()` throws the typed pending-consent refusal and yields no grant (**RN-R2** *Without a grant, nothing is transmitted and the refusal is typed*); `granted(at:)` is the only consenting constructor and always carries its date; `revoked()` equals `.notGranted` **including its absent date** (*Revocation leaves no residue*). Throwing, never `Bool`.
- [x] 3.2 GREEN create `Sources/ReleaseNotes/ReleaseNotesConsent.swift` (+ `ReleaseNotesGrant` with an **internal** `init`, `ReleaseNotesConsentProviding`, `FixedReleaseNotesConsent`) and `Sources/ReleaseNotes/ReleaseNotesError.swift`.
- [x] 3.3 RED same file, the disclosure (**RN-R2** *The disclosure names the host and what is revealed*): the CellarCore-supplied disclosure constant names `api.github.com`, states that a **repository name** is transmitted and that this reveals this Mac has the package installed and is about to upgrade it, and contains none of `anonymous`, `nothing about this Mac`, `no identifying`.
- [x] 3.4 RED structural, T6 (`IntegrityProhibitionTests` idiom): a public-surface enumeration of `ReleaseNotesGrant` finds **no public initialiser**, so the only producer is `authorise()`; a source scan of `Sources/ReleaseNotes/` finds no `import SecurityKit` and no `ScanConsent`/`AdvisoryError` symbol, which is what makes **RN-R2** *The security-scan grant does not authorise release notes* structural rather than conventional.
- [x] 3.5 RED create `Tests/ReleaseNotesTests/ReleaseNotesCredentialStoreTests.swift` (**TM6**, T13, `SecurityKitTests/CredentialStoreTests` idiom): `KeychainReleaseNotesCredentialStore.baseQuery` declares a **generic password**, service `com.juancasanueva.cellar.github-pat`, `kSecAttrAccessibleAfterFirstUnlock`, and `synchronizable: false` (**RN-R7** *The token has exactly one home*). No live Keychain call is made, for the shipped reason.
- [x] 3.6 GREEN create `Sources/ReleaseNotes/ReleaseNotesCredentialStoring.swift`: the protocol (`personalAccessToken()`, `store(personalAccessToken:)`, `removePersonalAccessToken()`) and `KeychainReleaseNotesCredentialStore`. Same shape and same rules as `AdvisoryCredentialStoring`, distinct service name — one mechanism applied twice, **not** a second set of rules (D2).
- [x] 3.7 RED structural secret containment (T13, `SecurityCompositionSupport` comment-stripping idiom): a `#filePath`-rooted scan of `Sources/ReleaseNotes/` finds no `UserDefaults`, no `@AppStorage`, and no `print`/`NSLog`/`os_log` anywhere on a token path (**RN-R7** *The token has exactly one home*, *A stored token is removable and never echoed*).

## Phase 4: Release wire and tag matching (**RN-R5**, T3)

- [x] 4.1 RED create `Tests/ReleaseNotesTests/GitHubReleaseDecoderTests.swift`: `releases-git-populated.json` decodes to `[GitHubRelease]` carrying `tagName`, `name`, `body`, `isDraft`, `isPrerelease`, `publishedAt`, `htmlURL`; `releases-empty.json` decodes to `[]` (not `nil`, not a throw); one malformed element is skipped without costing the file.
- [x] 4.2 GREEN create `Sources/ReleaseNotes/GitHubRelease.swift`: `Decodable`-only model plus `GitHubReleaseDecoder` with `@concurrent` **on its own line before** `public static func decode(_:) async throws -> [GitHubRelease]`.
- [x] 4.3 RED create `Tests/ReleaseNotesTests/ReleaseTagMatcherTests.swift`, the five spec scenarios: `v2.44.0` matches version `2.44.0`; tag `2.44.0` matches exactly; **`2.43.0_1` matches `v2.43.0`** (formula revision stripped, and the suffix must not cause a miss); **`1.2.3,456` matches `1.2.3`** (cask build stripped); `v2.44.1`/`v2.45.0` against `2.44.0` is a **miss**, and neither is returned (**RN-R5**, all five).
- [x] 4.4 RED same file — **design T3 rules the spec deliberately carries no scenario for; they ship because this task names them**: `<name>-x`, `<name>_vx` and `release-x` shapes; case-insensitive comparison; a **draft release never matches** even on an exact tag; a **prerelease matches only on an exact tag**, never via the `v`-prefix or name-prefixed candidates. No fallback to newest, substring or nearest version.
- [x] 4.5 GREEN create `Sources/ReleaseNotes/ReleaseTagMatcher.swift`: `nonisolated static func match(version:packageName:in:)`, normalisation first, then the candidate table. Pure and reproducible without a network.

## Phase 5: The five outcomes and rate-limit status (**RN-R4**, **TM2**, T4, T5)

- [x] 5.1 RED create `Tests/ReleaseNotesTests/ReleaseNotesOutcomeTests.swift`: all five outcomes are reachable and mutually distinct; none is an empty body, empty string, `nil` or a never-settling pending state; each is discriminable without parsing free text (**RN-R4** *An empty releases list is its own state*, *Releases exist but none matches the version* incl. the inspected count and no nearest/latest substitute).
- [x] 5.2 RED same file: `isCacheable` is `false` for `.unavailable` and only for it (D3); `noReleaseMatchesVersion` carries repository, version, inspected count and `pageWasFull`; each `ReleaseNotesFailure` case — `blockedPendingConsent`, `rateLimited`, `unauthorized`, `httpStatus(Int)`, `transport`, `payloadTooLarge`, `malformedPayload`, `cancelled` — is distinct from the rate-limit reason and from every other.
- [x] 5.3 GREEN create `Sources/ReleaseNotes/ReleaseNotesOutcome.swift`: `ReleaseNotesOutcome`, `ReleaseNotesFailure`, `isCacheable`.
- [x] 5.4 RED create `Tests/ReleaseNotesTests/RateLimitStatusTests.swift` (**TM2**, T5): headers parse from `releases-git-populated.headers.txt` (a **200**) as well as `error-403-ratelimit.headers.txt`; missing headers yield `nil` fields, **never `0`**; `x-ratelimit-reset` epoch seconds decode to a `Date`; `isExhausted` is `remaining == 0`. Parsing from every response is design behaviour with no spec requirement — this task is why it ships deliberately.
- [x] 5.5 GREEN create `Sources/ReleaseNotes/RateLimitStatus.swift` with the header parse.

## Phase 6: The source seam — exactly one request (**RN-R3**, **RN-R7**, **TM1**, **TM7**, T8, T9, T15)

- [x] 6.1 RED create `Tests/ReleaseNotesTests/GitHubReleaseNotesSourceTests.swift` over a recording `URLProtocol` transport: one `releases(for:…)` call issues **exactly one** request to `/repos/{owner}/{repo}/releases?per_page=<injected perPage>`; the fetch entry requires a `ReleaseNotesGrant` (**RN-R3** *One opened request costs one request*). Assert the page size against the **injected** bound, never a literal `30`.
- [x] 6.2 RED same file (**RN-R3** *Acquisition carries no ambient state*): the session configuration is ephemeral with `urlCache == nil`, no cookie storage, `reloadIgnoringLocalCacheData`, and a byte limit set; a request issued while a validator is held carries `If-None-Match`, and one without a held ETag sends no such header; a `304` returns `.notModified` and triggers **no decode** (T8).
- [x] 6.3 RED same file (**RN-R7**): a stored token produces the authorization header (*A stored token authenticates the request*); no token still issues the request unauthenticated, settles normally, and produces no failure naming a missing token (*No token is not an error*). No credential other than this capability's token is carried.
- [x] 6.4 RED same file (**TM7**, T9): a body over the byte limit is refused as `.payloadTooLarge` with nothing decoded or cached, and an `expectedContentLength` over the limit refuses **before** the body is read.
- [x] 6.5 RED same file (**RN-R4**, **TM2**): `403` + `x-ratelimit-remaining: 0` → `.rateLimited` carrying `resetAt` — not `.httpStatus(403)`, not an absence, and **no automatic retry** (*A rate-limit refusal is distinct and carries its reset time*); `401` → `.unauthorized` claiming no reset or budget (*A rejected token is not a rate limit*); another non-success status → `.httpStatus(Int)`; a transport failure → `.transport`, never "publishes no releases" (*A transport failure is not a rate-limit refusal*).
- [x] 6.6 RED same file: `Task.checkCancellation()` before the request and before the decode; a cancelled load settles as `.cancelled`, a typed failure and never an error dialog.
- [x] 6.7 GREEN create `Sources/ReleaseNotes/ReleaseNotesSource.swift`: the `ReleaseNotesSource` protocol (singular by construction — no `[PackageID]` overload anywhere), `ConditionalValidators`, `ReleaseFetchOutcome` (`.notModified` | `.fetched([GitHubRelease], ETag?, RateLimitStatus)`), and `GitHubReleaseNotesSource(baseURL:byteLimit:perPage:)` — a `Sendable` struct owning the **only** `URLSession` in the target, using `bytes(for:)` — **not** `data(for:)` as originally written here, which cannot refuse an oversized response before the body is read (design → Apply-Time Amendments, item 1).

## Phase 7: The two-tier TTL cache (**RN-R6**, **D3**, **TM5**, T7)

- [x] 7.1 RED create `Tests/ReleaseNotesTests/ReleaseNotesCacheTests.swift` (**TM5**): a missing file, a byte-corrupt file, and a file at a different `ReleaseNotesSchema.currentVersion` each read as **cached nothing**, throw nothing, and adopt no partial entry set; a recording file seam proves each rejecting read **wrote, replaced and removed nothing** (**RN-R6** *A corrupt or mismatched store means cached nothing*).
- [x] 7.2 RED same file, TTL over an **injected `now`** and never `Date()`: a matched entry is fresh at 6 d 23 h and stale at 7 d 1 h (**RN-R6** *A matched body inside 7 days costs no request*, *A matched body past 7 days is re-asked*); a negative entry is fresh at 23 h and stale at 25 h (*A negative answer expires after 24 hours*); the key is `(repository, version)`, so two versions of one repository are two entries.
- [x] 7.3 RED same file (**D3**): a settled `403` rate-limit refusal leaves **no entry** for that `(repository, version)` when the store is read back (**RN-R6** *A rate-limit refusal is never cached*); the 200-entry cap drops the **oldest first**; `pruned(now:)` is idempotent.
- [x] 7.4 RED same file (**RN-R6** final clause, **RN-R9**): loading and saving this store reads and writes **no** catalog snapshot, invalidates no catalog cache, and moves no catalog schema version — asserted with the recording file seam over the catalog directory.
- [x] 7.5 GREEN create `Sources/ReleaseNotes/ReleaseNotesCache.swift`: `ReleaseNotesSchema.currentVersion = 1` as its **own** constant (never `CatalogSnapshot.currentSchemaVersion`), `ReleaseNotesCacheKey`, `ReleaseNotesCacheEntry` (`matchedTTL` 7 d / `negativeTTL` 24 h, `isFresh(now:)` tiered by outcome case, `etag`), `ReleaseNotesCacheFile` (`entryLimit = 200`, `pruned(now:)`), and the `ReleaseNotesCache` actor with atomic `.sortedKeys` writes (`AdvisoryCache` precedent).

## Phase 8: Markdown rendering and degradation (**RN-R8**, **TM3**, T10)

- [x] 8.1 RED create `Tests/ReleaseNotesTests/ReleaseNoteRenderingTests.swift` over `release-body-gfm.json`: a GFM table, a task list, `~~strikethrough~~`, an `@mention` and a bare autolink each render as **readable literal text** and are reported in `degradedConstructs`; the table's and task list's textual content is present in the prepared value; nothing throws (**RN-R8** *Unsupported GFM constructs survive as text*).
- [x] 8.2 RED same file: `release-body-malformed.json` and a body at the byte limit are each presentable without throwing, the total-failure path setting `renderedAsPlainText` (**RN-R8** *An unparseable body is still readable*); an empty body renders empty and never crashes.
- [x] 8.3 RED same file (**TM3**, **RN-R3** *A release body cannot cause a second egress*): an image reference produces **no URL a view could fetch**, and `browsableLink` refuses `javascript:`, `file:`, `data:` and a host-less URL while admitting http/https with a non-empty host — the `CaskInspection.browsableDownloadURL` allowlist, reused.
- [x] 8.4 RED same file: preparation never changes the outcome — a degraded body still reports a matched release, and a matched release whose body is the empty string reports **matched with an explicitly empty body**, distinct from both absences (**RN-R8** *An empty body is a matched release, not an absence*).
- [x] 8.5 GREEN create `Sources/ReleaseNotes/ReleaseNoteRendering.swift`: block-wise `AttributedString(markdown:)` with `.returnPartiallyParsedIfPossible`, `UnsupportedMarkdown`, `RenderedReleaseNote { blocks, degradedConstructs, renderedAsPlainText }`, `browsableLink`. Foundation only, no SwiftUI.

## Phase 9: The store and the one-request integration (**RN-R3**, **RN-R4**, T11, T15)

- [x] 9.1 RED create `Tests/ReleaseNotesTests/ReleaseNotesStoreTests.swift`: a per-`PackageID` generation counter means a second `load` for the same id cancels the first and only the later result lands; a failed reload keeps the previous `.notes` visible (last-good survival); `cancel(_:)` leaves state at the last good value.
- [x] 9.2 RED same file, the integration budget (T15): one `load` issues exactly **one** request; an immediate second `load` for the same `(repository, version)` issues **zero** (cache hit); a resolution failure issues zero; a consent refusal issues zero and settles as `.unavailable(.blockedPendingConsent)`; a rate-limited outcome issues no retry.
- [x] 9.3 RED same file: the `RateLimitStatus` parsed from a **200** reaches `store.rateLimit`, so the sheet can warn before the wall and D5's PAT field is actionable (T5, **TM2**).
- [x] 9.4 GREEN create `Sources/ReleaseNotes/ReleaseNotesStore.swift`: `@MainActor @Observable`, `@ObservationIgnored` internals, `private(set) var states: [PackageID: ReleaseNotesState]` and `rateLimit`, `load(_:version:candidates:)` (single package, no array form, no `.task` caller) and `cancel(_:)`.

## Phase 10: Structural guards and regression (**RN-R3**, **RN-R9**, T12, T13, T14)

- [x] 10.1 RED create `Tests/ReleaseNotesTests/ReleaseNotesEgressStructureTests.swift` (T12b, `SecurityKitTests/EgressStructureTests` + `SecurityCompositionSupport` comment-stripping idiom): a `#filePath`-rooted scan of `Sources/ReleaseNotes/` finds `URLSession`/`URLRequest` in **exactly one file**; that file's fetch entry point requires a `ReleaseNotesGrant`; and the target contains no `[PackageID]`, `submitBulk` or `prefetch` symbol.
- [x] 10.2 RED create `cellarTests/ReleaseNotesEgressCompositionTests.swift` (T12a — **recorded placement**: `OperationCenterBulk` lives in `BrewClient`, which `ReleaseNotes` may not see, so the only place that sees both is the app test target): with a recording network seam and a granted consent, 30 outdated packages submitted through `OperationCenterBulk.submitUpgrades` issue **zero** release-notes requests and never touch `ReleaseNotesStore` (**RN-R3** *A bulk upgrade issues zero GitHub requests*).
- [x] 10.3 RED regression (T14, **RN-R9** *The catalog footprint is unchanged*): `Tests/CatalogTests/CatalogFootprintTests.swift` runs **unchanged** — no edited bound, no re-based value, a **zero-line diff** — and passes beside this target. Do not touch that file.
- [x] 10.4 RED structural (**RN-R9**): assert `CatalogPackage`'s stored-property set is unchanged and `CatalogSnapshot.currentSchemaVersion` still reads `2`; and that the whole flow — resolve, fetch, match, cache, read back — spawns **no process**, asserted by the target graph (`ReleaseNotes` declares only `Catalog`, so `BrewProcess` is unreachable) plus a recording process seam (*The whole flow spawns no brew process*).
- [x] 10.5 RED `cellarTests/ReleaseNotesEgressCompositionTests.swift` (T13, cross-module half — **recorded placement**, same reason): `KeychainReleaseNotesCredentialStore.service` is asserted **different** from `KeychainAdvisoryCredentialStore.service`, compared as live symbols rather than as two copied literals.

## Phase 11: App layer — the product link, both entry points, the consent surface (**D4**, **D5**, T16, T17)

- [x] 11.1 `cellar.xcodeproj/project.pbxproj`: add **exactly four objects** and nothing else — (a) the `PBXBuildFile` `ReleaseNotes in Frameworks`; (b) its line in the `cellar` target's `PBXFrameworksBuildPhase` `files` list; (c) its line in the target's `packageProductDependencies`; (d) the `XCSwiftPackageProductDependency` with `productName = ReleaseNotes`, following the shipped `BC00000100000000000000NN` identifier convention. **No** build-setting, scheme, signing or synchronized-group change; new sources under `cellar/` need no pbxproj edit. Check: `BUILD`. Rollback = remove those same four objects, then `BUILD` again.
- [x] 11.2 RED create `cellarTests/ReleaseNotesCompositionTests.swift` (T16): the `ReleaseNotes` module is importable from the app target and a type from it resolves — this is 11.1's test, and it fails until the product link exists.
- [x] 11.3 Author the **consent-surface disclosure copy** (D1, design Open Question 2) as a named constant against the `SecurityConsentSheet` constants pattern: it names `api.github.com`, says a repository name is transmitted, says that this reveals this Mac has the package installed and is about to upgrade it, and claims no anonymity. This task authors **content**, not code; 11.4 proves its shape and 12.3 reviews its wording.
- [x] 11.4 RED `cellarTests/ReleaseNotesCompositionTests.swift` (T16): the disclosure is a **named constant, not a body literal** (`SecurityConsentSheet` precedent), and the composed sheet renders that exact constant.
- [x] 11.5 RED same file: the row and sheet models are plain `nonisolated` value types testable without instantiating a view — they carry the five outcomes as distinct presentable states, and a rate-limited state exposes the reset time and the PAT affordance rather than an absence phrasing.
- [x] 11.6 GREEN create `cellar/ReleaseNotes/ReleaseNotesConsentPreference.swift`: `@MainActor @Observable`, app-owned, holding the two `UserDefaults` keys (the grant is a preference; the PAT is a secret).
- [x] 11.7 GREEN create `cellar/ReleaseNotes/{ReleaseNotesSheet,ReleaseNotesConsentSheet,ReleaseNotesSection}.swift`: presentation only. The consent sheet carries the **PAT field with removal** (D5) beside the disclosure; the notes sheet renders `RenderedReleaseNote.blocks` and never fetches a remote image or follows a link automatically.
- [x] 11.8 GREEN `cellar/Installed/InstalledRow.swift`: one explicit "What's new?" action **beside** `MutationMenu` and never inside it — `MutationMenu` is the shared mutation surface driven by `OperationCenter`, and a network-touching read action there would hand every mutation call site an egress affordance. Shown only when the row is outdated (D4 primary).
- [x] 11.9 GREEN `cellar/Browse/PackageDetailView.swift`: one section with an explicit button, shown only when a repository resolves (D4 secondary, D6). Never on hover, appear or selection — no `.task` trigger anywhere.
- [x] 11.10 GREEN `cellar/cellarApp.swift`: construct the store, the consent preference, the Keychain store and the cache file URL; inject via `.environment`.
- [x] 11.11 RED then GREEN in `cellarUITests` (T17): without a grant, the outdated row's "What's new?" shows the **consent surface**, not a spinner and not an empty sheet; with a grant and a stubbed transport, a note renders; a rate-limited response shows the reset time and the PAT affordance and does **not** read as "no release notes".

## Phase 12: Close-out

- [x] 12.1 Run `FAST`, `APP`, `FULL` and `BUILD` green. Confirm the `@Test` count is strictly above the pre-change count and that no pre-existing assertion was deleted or weakened — `git diff -U0` over `Tests/`, `cellarTests/` and `cellarUITests/` must remove no assertion line, and `CatalogFootprintTests.swift` must show a **zero-line** diff.
- [x] 12.2 Document where the next reader looks: the digest-key trap and the `*.headers.txt` standard in `Tests/ReleaseNotesTests/Fixtures/GitHub/README.md`; a doc comment on `ReleaseNotesSchema.currentVersion` stating **why** it is independent of the catalog's; and, in `design.md` under *Apply-Time Amendments*, the two recorded placements from 10.2/10.5, the resolution of Open Question 1 (`per_page` stays 30, `pageWasFull` carries the honesty, tests assert the injected bound), and any other evidence-forced change — recorded, never absorbed silently.
- [x] 12.3 Surface the disclosure copy authored in 11.3 to the user for a wording review **before the PR opens** (slice-2 10.3 precedent). Task 11.4 proves it is a constant and renders; it does not prove the wording is honest enough. This closes design Open Question 2 here, not at verify.
- [x] 12.4 Before any revert of this change: remove a stored PAT from the consent surface **first**. A revert leaves the Keychain item with nothing left to read it. Record this in the change's rollback note beside the four pbxproj objects.
