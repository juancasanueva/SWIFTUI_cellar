# Design: M4 Security

Derived from `proposal.md` and the three spec deltas under `specs/`. Probe input: U1 (obs 7451).

## Technical Approach

A new target `SecurityKit` depends on **`Catalog` only**, keeping it brew-free and subprocess-free.
`Persistence` gains a second inward edge (`Persistence → {BrewClient, SecurityKit}`) for
`DismissedCVE`; `BrewClient` gains nothing, which is what makes the comparator structurally
unreachable from the snooze path. Inside `SecurityKit`: `Sendable` value types and a pure matcher, an
`actor` scan engine shaped like `CatalogSyncEngine`, an `actor` advisory cache shaped like
`DiskUsageCache`, a `@MainActor @Observable` `SecurityStore` shaped like `CleanupStore`, and two
inspector protocols whose real implementations call Security.framework and `getxattr`/`listxattr`.

Because no CellarCore target may see both `BrewClient` and `SecurityKit`, the **app target owns every
composition point** between them: the advisory query builder, the artifact locator, and the refresh
coordinator all live under `cellar/Security/`. Fix-version upgrade is the existing
`MutationCommand.upgrade` through the existing `OperationCenter`.

## Architecture Decisions

| Choice | Rejected | Rationale |
|---|---|---|
| `SecurityKit → Catalog` only; `Persistence → SecurityKit`; no `BrewClient` edge | SecurityKit inside BrewClient; `BrewClient → SecurityKit` | Keeps the target brew-free (CS1) and makes the comparator unreachable from the snooze *decision*, which is what `local-package-metadata` now requires. |
| New `AdvisorySource` protocol, sibling to `CatalogSource` | Reuse `CatalogSource`/`HTTPCatalogSource` | `CatalogSource` is a conditional GET keyed by a `CatalogResource` enum streaming a 31 MB body to disk. OSV is a POST with a JSON body; NVD a keyed GET. Sharing would widen a shipped, archived capability and drag `CatalogSyncError` into advisory semantics. The **discipline** is copied verbatim, the type is not. |
| `data(for:)` with an 8 MiB guard, not `download(for:)` | File-staged downloads | Advisory bodies are KB-scale and there is no 304 path; the classify-before-opening-the-temp-file lesson is specific to file-based fetches. |
| Ecosystem mapping as a compiled Swift literal table with per-entry provenance | JSON resource; heuristic name matching | U1 proved name matching is dominated by identity collisions (curl→RubyGems, coreutils→uutils). A literal table is compile-checked, needs no bundle plumbing in a library target, and has no runtime decode failure mode. Real coverage is ≈3–5%, so a single-digit table is correct. |
| Four-case `CVEScanOutcome` with no boolean collapse | `[Finding]` + `isEmpty`; optional findings | "No source answered" must never render as "no vulnerabilities". The type makes the collapse unrepresentable. |
| **Affectedness is OSV's answer; strict SemVer governs only the fix-version offer** | Local range evaluation; gating coverage on strict SemVer | OSV `querybatch` matches the queried version server-side against its own declared ranges. Deciding affectedness locally would re-implement per-ecosystem version algebra — the exact landmine the M2 ruling names. See the version boundary below. |
| Comparator typed on `StrictSemVer`, never on `String` | Homebrew `Version`/`Token` port; prefix comparison | A function that cannot accept two `String`s cannot be misapplied to Homebrew version strings; the guard becomes a type-level fact plus a manifest-reachability assertion. |
| Advisory cache is an `actor` over one JSON file beside `disk-usage-v1.json` | SwiftData rows; per-key files; in-memory only | `DiskUsageCache` is the shipped precedent for exactly this shape, and the spec requires offline-readable findings. SwiftData would put a user-recoverable store behind derived, re-fetchable data. |
| Consent is a preference (`UserDefaults`); the NVD key is a credential (Keychain) | Both in `@AppStorage`; both in Keychain | A boolean+date is not a secret; an API key is. |
| Assessable formula-keg artifacts are `bin/`+`sbin/` Mach-O regular files of the primary keg | Whole-keg walks; casks only | Whole-keg walks are unbounded and dominated by headers, man pages and scripts that carry no signature. `bin/`/`sbin/` executables are what a user runs, and a 4-byte magic sniff bounds the cost. Casks-only would violate the spec's "formula keg contents where a signed, assessable artifact exists". |

## The Version Boundary (coverage vs. fix comparison)

Two different version strings, two different rules. Conflating them is what would break the spec.

1. **Query version** — what OSV is asked about. Derived from the installed primary keg's version by a
   *lexical* decomposition: a trailing `_<digits>` Homebrew packaging-revision suffix is removed
   (`1.2.3_1 → 1.2.3`). This is a split, not an ordering: nothing is compared, ranked or preferred.
   Its failure direction is safe — querying upstream `1.2.3` may report an advisory the Homebrew
   revision already patched, a *visible false positive*, which is the direction this codebase has
   repeatedly chosen over a silent false negative.
2. **Coverage** — decided by OSV, not locally. If the query version is interpretable in the mapped
   ecosystem's scheme, the package is queried and the outcome is `covered(findings)` or
   `covered(clean)` from OSV's own range evaluation. If it is *not* — `2024-01-05`, `r5`, `8e` mapped
   to a SemVer ecosystem — nothing is queried and the outcome is
   `notCovered(.unsupportedVersionScheme)`, because an answer computed against a string OSV would
   have coerced is worse than an honest gap. That is the case's one remaining legitimate trigger, and
   it is why the case survives rather than being removed.
3. **Fix comparison** — a later, separate step over the **installed** string (not the query version)
   and the advisory's fixed string, both of which must parse as strict SemVer.

Consequence, stated so it cannot surprise: an installed `1.2.3_1` is **covered** (queried as `1.2.3`)
and, when OSV reports a fix at `1.2.4`, produces a **finding** that says "fix published, comparison
not possible for this version scheme" — because `1.2.3_1` is not strict SemVer. This is exactly the
spec's scenario. A Homebrew revision therefore never suppresses coverage and never yields an ordering
verdict.

## Interfaces, Ownership, and Algorithms

- **Values.** `CVEScanOutcome` is `.covered(findings: [VulnerabilityFinding])`, `.covered(clean:)`
  (distinct cases, no `isEmpty` collapse), `.notCovered(NotCoveredReason)`,
  `.unavailable(AdvisoryError)`. `NotCoveredReason` uses the spec's literals exactly:
  **`.unmapped`, `.kindUnsupported`, `.unsupportedVersionScheme`** — no other case exists, and there
  is no `isClean` accessor other than `case .covered(clean:)`. `SeverityTier` is
  `.critical/.high/.medium/.low/.none/.unrated`; tiering prefers CVSS v4.0 → v3.1 → v3.0 → v2, else an
  advisory-published severity, else `.unrated`, which sorts and renders in its own bucket.
  `ResultFreshness` is `.live` or `.cached(fetchedAt:)`. `ScanProvenance` mirrors
  `CleanupParserProvenance`: `scannedAt`, `matcherVersion: Int`, `mappingRevision: Int`, per-source
  `skippedRecordCount`, `enrichmentAttempted/Succeeded`.
- **Acquisition.** `AdvisorySource: Sendable` exposes `discover([AdvisoryQuery]) async throws -> AdvisoryDiscovery`
  and `enrich([CVEID]) async throws -> AdvisoryEnrichment`. `OSVSource` POSTs `/v1/querybatch` for the
  mapped subset (response is `{id, modified}`) and hydrates via `/v1/vulns/{id}`; `NVDSource` GETs
  `cves/2.0?cveIds=` in batches of ≤100 for already-discovered identifiers only — no request ever
  names an installed package, so volume scales with findings. Both use
  `URLSessionConfiguration.ephemeral`, `urlCache = nil`, `.reloadIgnoringLocalCacheData` on config and
  request, an 8 MiB byte guard, and status classified before decode. Base URLs are `static let`
  constants; no host is built from user input.
- **Decoding.** `OSVWire`/`NVDWire` follow the `InstalledDecoder` rule: a malformed **envelope** fails
  the request; a malformed **record** is skipped *and counted* into `ScanProvenance.skippedRecordCount`.
- **Matching.** `CVEMatcher` is a pure `Sendable` struct over values. It composes OSV's returned
  advisories with the mapping entry and the dismissal lookup; it performs no name similarity, no
  vendor inference and no keyword matching. Absent from the table ⇒ `.notCovered(.unmapped)`; cask ⇒
  `.notCovered(.kindUnsupported)`.
- **Versions.** `HomebrewRevision.split(_: String) -> (upstream: String, revision: Int?)` is the
  lexical suffix split (no comparison operator anywhere in it).
  `StrictSemVer.parse(_: String) -> StrictSemVer?` accepts only `MAJOR.MINOR.PATCH` with optional
  SemVer prerelease/build and numeric identifiers without leading zeros. `FixVersionComparison` is
  `.fixedAtOrBefore`, `.stillAffected`, `.noFixPublished`, `.fixUnknown`, `.notComparable(scheme:)`.
  Comparator entry points take `StrictSemVer` only.
- **Cache.** `AdvisoryCaching { func load() async throws -> AdvisoryCacheFile?; func save(_:) async throws }`
  with `actor AdvisoryCache` — the `DiskUsageCache` shape verbatim. One JSON file at
  `~/Library/Caches/Cellar/security-advisories-v1.json`, sibling to `disk-usage-v1.json` (URL built in
  `cellarApp`, as `diskCacheURL` already is). `AdvisoryCacheFile` holds `revisionOrdinal: Int` and
  `entries: [AdvisoryCacheEntry]`. The key is the spec's:
  `AdvisoryCacheKey(sourceID: AdvisorySourceID, packageID: PackageID, version: String)`; the entry
  carries `outcome`, `fetchedAt`, `advisoryModified: Date?` (newest `modified` across its advisories),
  `mappingRevision`, `matcherVersion`.
  **TTL = 24 h**, chosen to equal `staleAfter` and the approved daily cadence: a shorter TTL would
  make every scheduled scan a full re-query with no cache benefit, and a longer one would let a
  consented daily scan read its own cache and never actually refresh. The TTL therefore serves
  exactly the within-day repeats — relaunch, manual refresh, post-mutation re-scan — and never
  suppresses the scheduled refresh. **Two independent invalidations**, per the spec: (a) TTL expiry or
  a `mappingRevision`/`matcherVersion` mismatch against the running build, so a corrected table or a
  fixed matcher can never be masked by stale entries; (b) a `querybatch` `modified` newer than the
  entry's, which forces re-hydration of that advisory even inside TTL.
  **Load/adoption interaction:** `SecurityStore.loadCache()` runs before any network work and adopts a
  snapshot minted at the file's persisted `revisionOrdinal`; a live scan mints `persisted + 1` and
  persists it on save. Monotonicity therefore survives relaunch, and a slow cache load landing after a
  fast live scan is rejected by the ordinal guard instead of blanking fresh results — the
  `CatalogStore.loadCache()` → `adopt` precedent. Every cached outcome is published with
  `.cached(fetchedAt:)` and rendered with its age; nothing stale is presented as fresh.
- **Store.** `SecurityStore` is `@MainActor @Observable`, `@ObservationIgnored` internals,
  `private(set)` state, per-`SecurityScope` (`.cveScan`, `.integrity`) generation UUIDs, task map, and
  `lastGood` survival exactly as `CleanupStore`. Adoption *additionally* requires a strictly greater
  `SecurityScanRevision.ordinal` as `CatalogStore.adopt` does; a duplicate joins the in-flight
  adoption, an older returns. Two guards, two questions: the generation kills a superseded *task*, the
  ordinal kills a late-arriving older *snapshot*. A partial scan is adopted as partial and never as
  complete.
- **Scheduling.** `actor SecurityScanEngine` mirrors `CatalogSyncEngine`: single-flight by token,
  drain-then-restart on cancellation, one-observer `AsyncStream<SecurityScanEvent>`, `scanIfStale()`,
  `runRefreshLoop()`. `SecurityRefreshPolicy` **mirrors `CatalogRefreshPolicy`'s deliberate split**:
  `staleAfter: TimeInterval = 24 * 60 * 60` compared against the cache's wall-clock `fetchedAt`, and
  `pollGranularity: Duration = .seconds(15 * 60)` for the loop's sleep — because a single 24 h
  monotonic sleep does not advance while the machine is asleep, so a laptop closed overnight would
  wake with no pending re-scan (`CatalogSyncEngine.swift:149`). It also carries `maximumAttempts`,
  `backoff` and `payloadByteLimit` for the same reasons `CatalogRefreshPolicy` does. Every egress path
  checks `ScanConsent` first and emits `.blockedPendingConsent` rather than parking silently; off is
  fully off, and the cache stays readable.
- **Credentials.** `AdvisoryCredentialStoring` fronts the Keychain (`kSecClassGenericPassword`,
  service `…cellar.nvd-api-key`, `kSecAttrAccessibleAfterFirstUnlock`). Tests use an in-memory fake;
  no test touches the real Keychain, and the key never reaches `UserDefaults`, a plist, or a log.
- **Integrity.** `CodeSignatureInspecting` and `QuarantineInspecting` are protocols;
  `SecurityFrameworkSignatureInspector` uses `SecStaticCodeCreateWithPath`,
  `SecCodeCopySigningInformation`, `SecStaticCodeCheckValidity` against `"notarized"` and
  `anchor apple generic`, and `SecAssessmentTicketLookup`. `ExtendedAttributeQuarantineInspector`
  reads `com.apple.quarantine` and `com.apple.provenance` via `listxattr`/`getxattr`, decodes the
  `flags;hexTimestamp;agentName;UUID` shape from fixtures, and preserves the raw value verbatim
  alongside typed components, reporting any unrecognised component as unknown.
  `ArtifactIntegrityEngine.inspect` is `@concurrent` and streams
  `AsyncThrowingStream<ArtifactIntegrityEvent>` with `Task.checkCancellation()` per artifact, exactly
  as `DiskUsageEngine.scan`; a per-artifact failure becomes a typed `.couldNotAssess(reason)` event,
  never a stream termination. Because online ticket lookup can reach the network it sits behind the
  same consent gate; without consent the verdict is the stapled result or
  `.couldNotAssess(.onlineLookupRequiresConsent)`. No public surface accepts a write: there is no
  `removexattr` call site anywhere in the target.
- **Artifact scope and assessability.** `ArtifactLocation(packageID:url:kind:)` is a SecurityKit value.
  `ArtifactAssessability.classify(_ url: URL) -> AssessableArtifactKind?` is a pure filesystem
  predicate in SecurityKit — a bundle (`.app`, `.framework`, `.xpc`, `.bundle`) whose
  `Contents/MacOS` executable exists, or a **regular file (not a symlink) whose first four bytes are a
  Mach-O magic** (`0xfeedface`, `0xfeedfacf`, `0xcafebabe`, `0xbebafeca`). Anything else returns `nil`
  and is silently out of scope, which is what "only where a signed, assessable artifact exists" means
  operationally. **Who builds the list:** the **app-side** `ArtifactLocator` in `cellar/Security/`,
  because it needs `HomebrewRoots` (`DiskUsage`) and `InstalledPackage.primaryKeg` (`BrewClient`)
  *and* must emit SecurityKit values, and no CellarCore target sees all three. It enumerates cask
  artifacts from the Caskroom and, for each formula, only the primary keg's `bin/` and `sbin/`, then
  filters every candidate through `ArtifactAssessability.classify`. It enumerates no other location,
  so `/Applications` is never swept.
- **Advisory query construction.** `SecurityQueryBuilder` in `cellar/Security/` builds
  `[AdvisoryQuery]`. Primary-keg selection has an owner and it is not SecurityKit:
  `InstalledDecoder.primaryKeg` (linked keg wins, else newest) already lives in `BrewClient` and
  `InstalledPackage.primaryKeg` exposes it, so the builder reads that existing projection, applies
  `HomebrewRevision.split`, consults `EcosystemMapping`, and emits one query per mapped formula.
  Unmapped formulae, casks, and uninterpretable versions never become queries — they become the
  corresponding `notCovered` outcome without egress.
- **Persistence.** `SchemaV2` lists `[PackageMeta, Snooze, HistoryEntry, DismissedCVE]`; the three V1
  models are byte-identical. `DismissedCVE` holds `cveID`, `kindRaw`, `name`, `version`, `dismissedAt`,
  `note: String = ""` — primitives only, no `@Relationship`, no `@Transient`, absence is the empty
  string, `#Unique<DismissedCVE>([\.cveID, \.kindRaw, \.name, \.version])`. `MetadataMigrationPlan`
  becomes `schemas: [SchemaV1, SchemaV2]`, `stages: [.lightweight(from: SchemaV1, to: SchemaV2)]`;
  `PersistenceContainer.container` opens `Schema(versionedSchema: SchemaV2.self)`.
  `DismissalLookup = (DismissalKey) -> DismissedCVERecord?` mirrors `MetadataLookup`; `Persistence`
  publishes a `DismissalSnapshot` value, never a `@Model` instance. Dismissal is scoped to the exact
  version, is enumerable and reversible, changes no coverage state, and an upgrade re-surfaces the
  finding without user action.
- **App.** `.security` joins `AppSection` between `.cleanup` and `.history` (`checkmark.shield`).
  `SecurityView` groups by coverage with sections ordered **Vulnerable → Not covered → Clean →
  Unavailable**; four distinct counts survive aggregation and the Not-covered section renders with its
  count even at zero findings. `SecurityFindingDetail` frames every finding as
  "Reported for `<ecosystem>/<package>` `<version>`", links the OSV and NVD records, shows freshness
  and provenance, and offers dismissal; its upgrade button submits `MutationCommand.upgrade(target)`
  and states plainly that it offers Homebrew's current `catalogVersion` whenever that differs from the
  advisory's fixed version. Identifiers: `security-coverage-{state}`, `security-finding-{cveID}`,
  `security-dismiss-{cveID}`, `security-integrity-{package}`, `security-freshness`, `security-consent`.
- **Concurrency.** Both new targets are `.swiftLanguageMode(.v6)`. Engine and cache = `actor`; matcher,
  mapping, DTOs and value projections = `Sendable`, `nonisolated`; store = `@MainActor`; inspectors and
  the integrity sweep = `@concurrent`, off-main, per-item cancellable. No `@unchecked Sendable`, no
  `nonisolated(unsafe)`.

## Guard Reconciliation (`local-package-metadata`)

The existing `SnoozeProjectionTests.noVersionComparatorExists` **is extended, not preserved
byte-identically.** Snooze *behaviour* stays byte-identical; the *guard* grows, exactly as the delta
requires. The evolved test asserts, over sources with comments stripped:

1. the same forbidden comparator tokens (`compare(`, `.numeric`, `NumericSearch`, `versionCompare`,
   `isNewer`, `isOlder`, `precedes`, `<=`, `>=`) are absent — unchanged;
2. the positive equality anchor `snoozedVersion == candidate` is present, so the scan cannot pass
   vacuously — unchanged;
3. **new:** no `import SecurityKit` and no textual reference to `SecurityKit`, `StrictSemVer`,
   `FixVersionComparison` or `HomebrewRevision` appears in those sources;
4. **new:** at the manifest level (in `PackageGraphTests`), `BrewClient` declares no `SecurityKit`
   dependency and cannot reach it transitively — the reachability half of "structurally unreachable".

**Ownership tension, named and resolved.** `local-package-metadata` spans two targets: the snooze
*rule* lives in `BrewClient`, its *storage* in `Persistence`. `Persistence` now imports `SecurityKit`
for `DismissedCVE`, which belongs to `vulnerability-scanning`, not to this capability. The rule is
therefore **file-scoped, not target-scoped**, and that is the only non-vacuous reading: the delta's
prohibition is on snooze inputs, stored fields and projections accepting an ordering, and a
target-wide reading would forbid a `Persistence` edge the proposal already approved for an unrelated
model. "This capability's sources" is enumerated exactly as:

- `Sources/BrewClient/PackageMetadata.swift` — the rule
- `Sources/BrewClient/InstalledFilterMode.swift` — the outdated projection
- `Sources/Persistence/MetadataStore.swift` — snooze/unsnooze writes and `snoozedVersion` reads
- `Sources/Persistence/LocalStores.swift` — snapshot publication
- `Sources/Persistence/SchemaV1.swift` and `Sources/Persistence/SchemaV2.swift` — the `Snooze` model

Assertions (1)–(2) apply to the two `BrewClient` files (where the rule lives); assertion (3) applies
to **all six**. `Sources/Persistence/DismissalStore.swift` is deliberately not in the list because it
implements a different capability. To keep that from being an allow-list escape — which the delta
forbids — the guard states it **exhaustively and positively**: a scan of the whole
`Sources/Persistence/` directory asserts `DismissalStore.swift` is the *only* file containing
`import SecurityKit`. A second import anywhere in `Persistence` fails the suite and forces a design
conversation rather than passing quietly.

## Data Flow

```text
SecurityView → SecurityStore ──adopt(ordinal, generation)── SecurityScanEngine (actor, single-flight)
     │              ▲ loadCache (ordinal N)                        │ consent gate
     │              └── AdvisoryCache (actor, TTL 24h + modified) ──┤ scan mints ordinal N+1
     │                                                             ├─ EcosystemMapping → OSVSource.discover
     │                                                             ├─ NVDSource.enrich(cveIds)  [findings only]
     │                                                             └─ CVEMatcher (pure) → [CVEScanOutcome]
     ├─ SecurityQueryBuilder (app) ← InstalledPackage.primaryKeg (BrewClient)
     ├─ ArtifactLocator (app) ← HomebrewRoots (DiskUsage) → ArtifactIntegrityEngine (@concurrent stream)
     ├─ DismissalLookup ← Persistence(SchemaV2)
     └─ upgrade → OperationCenter.MutationCommand.upgrade   [unchanged spine]
```

## File Changes

| Files | Action |
|---|---|
| `Packages/CellarCore/Package.swift` | Modify — `SecurityKit` target + product, `SecurityKitTests` with `resources: [.copy("Fixtures")]`, `Persistence → SecurityKit`. |
| `Sources/SecurityKit/{AdvisorySource,OSVSource,NVDSource,OSVWire,NVDWire}.swift` | Create — acquisition and tolerant DTOs. |
| `Sources/SecurityKit/{CVEMatcher,EcosystemMapping,SecurityModels,StrictSemVer,HomebrewRevision,ScanProvenance}.swift` | Create — pure matching, curated table, value vocabulary, comparator, lexical suffix split. |
| `Sources/SecurityKit/AdvisoryCache.swift` | **Create — `AdvisoryCaching` + `actor AdvisoryCache`, `AdvisoryCacheKey/Entry/File`, TTL and `modified` invalidation, persisted revision ordinal.** |
| `Sources/SecurityKit/{SecurityScanEngine,SecurityRefreshPolicy,SecurityStore,ScanConsent,AdvisoryCredentialStoring}.swift` | Create — lifecycle, split stale/poll policy, store, consent, Keychain seam. |
| `Sources/SecurityKit/{CodeSignatureInspecting,QuarantineInspecting,ArtifactAssessability,ArtifactIntegrityEngine}.swift` | Create — inspectors, assessability predicate, streamed sweep. |
| `Sources/Persistence/{SchemaV2,MetadataMigrationPlan,PersistenceContainer,DismissalStore}.swift` | Create/modify — additive stage, `DismissedCVE`, value projection. |
| `cellar/Security/{SecurityView,SecurityFindingDetail,ArtifactIntegrityPanel,SecurityConsentSheet}.swift` | Create — presentation. |
| `cellar/Security/{SecurityQueryBuilder,ArtifactLocator,SecurityRefreshCoordinator}.swift` | **Create — the three app-owned composition points between `BrewClient`/`DiskUsage` and `SecurityKit`.** |
| `cellar/Shell/AppSection.swift`, `cellar/{ContentView,cellarApp}.swift` | Modify — section, selection, store/engine/cache construction, advisory cache URL beside `diskCacheURL`. |
| `Tests/SecurityKitTests/**` | Create — RED coverage and fixtures. |
| `Tests/PersistenceTests/MigrationTests.swift`, `Tests/CatalogTests/PackageGraphTests.swift`, `Tests/BrewClientTests/SnoozeProjectionTests.swift` | Modify — V1→V2 migration, manifest reachability, the extended snooze guard. |

Note on placement: the shipped `DiskUsageRefreshCoordinator` lives in
`Packages/CellarCore/Sources/BrewClient/`, not in the app. `SecurityRefreshCoordinator` cannot follow
it there — no CellarCore target may import both `BrewClient` and `SecurityKit` — so it is the
*pattern* that is reused, in the app target, and the location deliberately differs.

## Testing Strategy

Swift Testing, strict TDD, RED before GREEN in this order: wire decode (envelope fails, record skips
and counts) → mapping table shape and `unmapped ⇒ notCovered(.unmapped)` → `HomebrewRevision.split`
and `StrictSemVer` parse corpus (U5) → the version boundary matrix (query version vs. coverage vs. fix
comparison, including the spec's `1.2.3_1`/`1.2.4` finding) → matcher coverage-state matrix
(exhaustive over all four states, plus the aggregation test that four counts survive) → severity
tiering including `.unrated` → cache TTL, `modified` invalidation, version-bump invalidation, offline
read with age, and ordinal continuity across a simulated relaunch → store generation/ordinal/last-good
and partial-never-adopted-as-complete → consent gating (zero egress before consent, proven by a
recording fake source; off means no request and no scheduled run) → dismissal persistence and
`V1 → V2` migration → `ArtifactAssessability` predicate over fixture files → inspector fakes and typed
`.couldNotAssess` → structural guards.

Structural guards, all as asserted facts: (1) `PackageGraphTests` gains
`graph["SecurityKit"] == ["Catalog"]`, `reachable(from: "SecurityKit")` disjoint with
`{BrewProcess, BrewClient, DiskUsage, Persistence}`, and `reachable(from: "BrewClient")` not
containing `SecurityKit`; (2) the extended snooze guard exactly as specified above, including the
exhaustive `Sources/Persistence/` import scan; (3) a no-subprocess scan of `Sources/SecurityKit/` for
`Process`, `posix_spawn`, `NSTask`, `/usr/bin/`, `spctl`, `codesign`, `xattr`, plus a no-write scan for
`removexattr`/`setxattr` and a host-literal scan admitting only the two constant base URLs.

Fixtures meet the `Tests/BrewClientTests/Fixtures/Cleanup/` bar: byte-exact captures under
`Fixtures/{OSV,NVD,Quarantine,MachO}/`, a `README.md` recording endpoint, exact request body, capture
date and tool versions, and a `probe-manifest.txt` with the SHA-256 of every file. The U1 scratchpad
captures are re-captured to that standard during apply.

## Probe Deviation (deliberate, recorded)

The proposal's success criteria required U1/U2/U3/U5 recorded **before design closes**. **U1 is
closed** (obs 7451) and it is the only probe that could change *what M4 is* — it sized the feature and
confirmed the curated-table decision. **U2, U3 and U5 are deferred to apply-phase RED-test gates**, as
a deliberate deviation with this justification: none of them can change an architectural decision in
this document, only the fixture content of tests that do not yet exist. U2 fixes NVD's response shape,
U5 the version corpus, U3 the assessment latency and privilege result — all of them *inputs to tests*,
and running them now would produce captures that must be re-captured to the `Fixtures` standard during
apply anyway. The gates are therefore binding on apply, not on design: **U2 and U5 before the matcher,
version-boundary and comparator RED tests; U3 before the inspector RED tests.** The two questions they
could still move are recorded as Open Questions below with their design defaults.

## Threat Matrix

| Boundary | Applicability | Response / RED |
|---|---|---|
| Subprocess / process integration | **Applicable — by prohibition** | `SecurityKit` spawns nothing; Security.framework and `getxattr` replace `spctl`/`codesign`/`xattr`. Structural no-subprocess scan is RED first, with a recording process launcher asserting zero launches. |
| Executable-file classification | **Applicable** | `ArtifactAssessability` classifies bundles and Mach-O files; signature/notarization verdicts classify their trust. Every unknown outcome is typed `.couldNotAssess(reason)` and every unrecognised attribute component is `unknown`; nothing degrades to "signed" or "notarized". RED over the fake inspector matrix and fixture files. |
| Filesystem write during classification | **Applicable — by prohibition** | Read-only: no `removexattr`/`setxattr` call site, no relocation, no elevation prompt. RED: filesystem observer asserts no byte of an inspected artifact changed. |
| Network egress | **Applicable** | Two constant hosts, consent-gated, ephemeral session, no URL cache, 8 MiB guard, status before decode. RED: zero requests before consent; off means zero requests and zero scheduled runs; host-literal structural scan. |
| Documentation-like path classification | N/A — no such classification | None. |
| Git repository selection / commit / push state | N/A — no VCS automation | None. |
| PR commands | N/A — no PR automation | None. |

## Migration / Rollout

`SchemaV1 → SchemaV2` is a single additive `.lightweight` stage; V1 models are unchanged and every V1
rule is held. The app is pre-release, so no shipped store migrates. The advisory cache is derived data
in `~/Library/Caches/`: a corrupt or unreadable file yields no entries and a full scan, never an error
path, matching `DiskUsageCache`. Scanning is opt-in: nothing leaves the machine before consent,
findings read from cache offline with their age, and revoking consent stops all egress and all
scheduled work while leaving the cache readable. Rollback is the proposal's: remove the target,
product, and `Persistence` edge; delete `Sources/SecurityKit/`, `Tests/SecurityKitTests/`,
`cellar/Security/`; drop the `.security` case and its `cellarApp` construction; delete the V2 stage
and `DismissedCVE`; revert the extended guard to its archived form. Xcode project changes are file
reference and group membership only.

## Open Questions

*Reconciled at apply, task 18.4. Each answer carries the measurement that produced it.*

- [x] **U2**: whether a CVE published with only an OSV CVSS **vector string** and no `baseScore`
      yields a tier or stays `.unrated`. **Answered at the Phase 2 gate (task 2.2): the premise does
      not occur.** Across the live NVD capture, wherever a `cvssMetricV2/V31/V40` entry exists its
      `cvssData.baseScore` is present — vector and score always travel together. The design default
      `.unrated` stands, reached by two *different* real shapes instead: `metrics: {}` entirely (a
      record at `vulnStatus: "Received"`), and a **non-CVSS** `metrics` entry — `ssvcV203` carries no
      `cvssData` and sits beside genuine v3.1 scores on `CVE-2022-1941` and `CVE-2026-0994`. The
      second is a live decode hazard: iterating `metrics` and assuming every entry is a CVSS score
      mis-tiers a properly scored record. Task 3.5 was amended in the open rather than quietly
      followed; both replacement assertions are green. Fixtures: `NVD/cveids-response.json`,
      `NVD/cveids-unrated-response.json`.

- [x] **U3**: whether `SecAssessmentTicketLookup` succeeds unprivileged on macOS 26 for a Caskroom
      bundle. **Answered at the task 14.0 gate, and the answer is stronger than the question: it is
      not callable at all.** The symbol is present in the shipped `Security` binary and **absent from
      the public macOS 26.5 SDK** — there is no `SecAssessment.h` under the framework's `Headers/`,
      and `SecAssessment` appears nowhere in its module map — so `import Security` does not declare
      it and a build that calls it fails to compile. Reached through `dlsym` **for the probe only**,
      it returned `false` in under 0.2 ms for all four notarized casks, with and without the
      force-online flag, which is not a usable answer either.
      **Consequence, exactly as this document predicted:** the inspector never calls it, and
      non-stapled notarization is `.couldNotAssess(.assessmentUnavailable)` — a weaker feature, not a
      different architecture. Tasks 14.4 and 14.5 were amended in the open.
      The **supported** path was measured working and **local**: `SecStaticCodeCheckValidity` against
      `"notarized"` passed on four real casks at **euid 501 with no prompt**, in 22.6–452.7 ms, flat
      across five consecutive calls, scaling with bundle size rather than distance, and failing in
      **20.2 ms** for an ad-hoc binary rather than after a timeout. Transcript:
      `Fixtures/MachO/signature-probe-record.txt`. Verified live at MV-7 (obs 7465): all three
      identity fields match `codesign -dv --verbose=4` literally.

- [x] Delivery slicing versus `size:exception`. **Resolved before apply**: the user read the
      three-way split recommendation and chose a single PR, recording `size:exception` (obs 7456).
      The measured outcome is recorded honestly in task 18.3 — **22,887 changed lines, 1.57× the top
      of the forecast band**. The recommendation against granting the exception at this size stands
      as written; it was overruled deliberately, not by omission.

### Still open, carried forward with reasons

- [ ] **Coverage is ~4% and that is the feature's real limit.** The curated table maps seven
      formulae; MV-3 measured **Clean 7 / Not covered 163** over a 170-package inventory. The
      declared fix is the **v1.1 local advisory index** — shipping a compiled index so coverage stops
      being bounded by a hand-written table. Registered rather than deleted because "not covered" is
      the honest state this release ships, and the next release is where it shrinks.
- [ ] **The mapping table's growth path.** Seven entries were curated by hand with per-entry
      provenance. There is no process yet for adding an eighth safely — U1 proved name matching is
      dominated by identity collisions (`curl` → RubyGems, `coreutils` → uutils), so growth cannot be
      automated from names alone. Open until the v1.1 index either replaces the table or gives it a
      verification procedure.
- [ ] **`the-unarchiver`-shaped casks yield no artifact.** One of ten installed casks leaves a stale
      Caskroom directory that `SecStaticCodeCreateWithPath` rejects with `-67028`. The panel shows
      nothing for it rather than an unassessable row saying why. Pinned by
      `aStaleCaskroomDirectoryShellYieldsNothing`; a visible "not assessable" row is the fix, and it
      is not in this change.
