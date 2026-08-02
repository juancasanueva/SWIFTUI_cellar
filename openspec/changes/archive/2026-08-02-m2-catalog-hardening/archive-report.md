# Archive report: m2-catalog-hardening

**Change**: `m2-catalog-hardening` — M2 slice **M2-0** ("M2 Prelude — Catalog Hardening") of the
four-slice M2 plan accepted in Engram `#7065`. Behaviour-preserving hardening of the M1 exemplars
that M2's new stores were about to copy.
**Closed**: 2026-08-02 · **Artifact store**: hybrid (OpenSpec files + Engram, project
`swiftui_cellar`)
**Status at close**: shipped and merged to `main`. SDD cycle complete, with one deliberately cut
phase carried forward as a follow-up.

This report is the terminal record of the cycle. Where it disagrees with `apply-progress` (#7072),
`tasks` (#7071) or `verify-report` (#7074), those are intermediate snapshots and this report states
the final state.

## Final state

| Fact | Value at close |
|---|---|
| Delivery | Single PR **#3** — <https://github.com/juancasanueva/SWIFTUI_cellar/pull/3> (`feature/m2-catalog-hardening` → `main`), merged by the user |
| Merge commit | **`b0ef70e`** on `main`, tree **`504f956`** — byte-identical to the reviewed candidate |
| Commits | **11** on top of `cc373e8` after the history rewrite (see below) |
| Tasks | **27 of 31** checked in the archived `tasks.md`. Phase 5 (5.1–5.4) **CUT**, not stale — see "Intentional partial archive" |
| Tests (package) | **243** `@Test` in **36** suites, green over **10 consecutive runs** — `swift test --package-path Packages/CellarCore` (214 / 33 suites at M1 close, **+29, zero deletions**) |
| Tests (release latency gate) | **2/2** — p95 preserved under the 8 ms ceiling with the index build moved off the main actor |
| Tests (app scheme) | `xcodebuild test … -skip-testing:cellarUITests` → `** TEST SUCCEEDED **` |
| Lint | `swiftlint` clean on every changed `.swift` file |
| Verify verdict | **PASS WITH WARNINGS** — 0 blockers, 0 CRITICAL, 2 WARNING, 3 SUGGESTION; **6/6** requirements, **22/22** scenarios COMPLIANT |
| Verify evidence | `evidence_revision sha256:8964a2fa1543a5db075248cd88a8381d5e8a85f15dacce1850a883518dcf3e78` |
| Native review | lineage **`review-93ca396315542808`**, reliability lens, full 28-file / 2,311-line branch diff — receipt **approved**; `pre-push` and `pre-pr` gates **ALLOW** |
| Review findings | 0 BLOCKER / 0 CRITICAL / **3 WARNING** / **3 SUGGESTION** |
| Authored diff | **1,586** changed lines under `Packages/` (1,473 insertions + 113 deletions) against the 1,500-line budget — **accepted `size:exception`** |
| Delivery strategy | `single-pr` with user-accepted `size:exception` (Engram `#7073`) |

`cellarUITests` is excluded from the app gate by the pre-existing template failure that reproduces
on `main`; this change touches zero files under `cellarUITests/`.

### The 86-line overrun

The authored diff came in 86 lines above the 1,500-line budget **after** Phase 5 was already cut.
The entire overrun is swiftlint-mandated **pure-move file splits**: `CatalogSyncEngine.swift` hit the
project's 400-line file limit, so M1's `CatalogResource` / `CatalogSyncError` / `CatalogDecoder`
extensions moved verbatim into a new `CatalogSyncSupport.swift` (+81 against matching deletions), and
two test suites were split the same way. Verification confirmed `CatalogSyncSupport.swift` is a pure
move that adds no public API. The user accepted the exception rather than re-slicing pure movement.

## History rewrite — commit-hash mapping (READ THIS BEFORE FOLLOWING ANY HASH IN `verify-report.md`)

After re-verification passed, the native `pre-push` gate denied publication: it walks the whole
**publication range**, not just the endpoint tree, and the range contained add/remove churn of
`openspec/changes/m2-mutations-installed/explore.md` — a file belonging to a *future, unproposed*
change. The branch history was rewritten (`git filter-repo --invert-paths` to strip the path, which
broke the M1 merge ancestry, then `rebase --onto main` to restore it).

**Every commit hash cited in `verify-report.md` and in `apply-progress` no longer exists on `main`.**

| Cited in | Hash | Status after the rewrite |
|---|---|---|
| `verify-report` — verified head | `b321703` | **Gone.** Content preserved; the verified tree is now reachable as merge `b0ef70e` / tree `504f956` |
| `verify-report` — superseded FAIL head | `6668eb7` | **Gone.** Was the swiftlint file-split commit |
| `verify-report` / `apply-progress` — explore.md untrack | `4bfe907` | **Gone.** Its whole purpose (keeping `explore.md` out of the change) is now achieved by the rewrite, so the commit is unnecessary |
| `apply-progress` — 12-commit list | `87b76d8 … 6668eb7` | **All gone.** Equivalent rewritten commits, 11 of them, sit on `cc373e8` |

**The delivered content is byte-identical to the reviewed and verified candidate** — tree `504f956`.
The pre-rewrite history is preserved locally at ref `backup/m2ch-prefilter` for audit; it is not on
`origin`. Read the verify report for *what was checked*, not for *where it lives*.

### Native review: two lineages, one delivered

| Lineage | Candidate | Outcome |
|---|---|---|
| `review-cd54f2e417da53ad` | A docs-only **workspace** candidate (the untracked `verify-report.md` + `explore.md`) | Approved, 3 WARNINGs — but **never delivered**. The receipt was undeliverable: `pre-commit` wanted the docs staged, `pre-push` wanted one-commit delivery. Superseded |
| **`review-93ca396315542808`** | The real branch diff, 28 files / 2,311 lines, started with `gentle-ai review start --base-ref main --committed-only=true` | **Approved.** Reliability lens. `pre-push` + `pre-pr` **ALLOW**. This is the governing receipt |

The archive gate is satisfied by `review-93ca396315542808`: `reviewGate.result: allow`, approved
terminal receipt matched to the final candidate tree `504f956`.

**Process lesson recorded**: clean the workspace *before* starting a delivery review — untracked
files silently become the candidate.

## Intentional partial archive: Phase 5 is CUT, not stale

The archived `tasks.md` contains **4 unchecked boxes** (5.1–5.4). This is *not* a stale-checkbox
reconciliation case and no boxes were ticked at archive time. Phase 5 (`CellarTestSupport` extraction
plus the cancellation-aware `TestClock`, design **D5**, proposal defect **#10**) was named in
`tasks.md` *before apply started* as the pre-agreed cut point if the diff crossed 1,500 lines. It did,
so the cut was taken. The phase heading in `tasks.md` carries the deferral note in the same words.

Leaving those boxes unchecked is the honest audit trail: the work is genuinely not done. It is
carried as follow-up **#3** below, and `Tests/{CatalogTests,BrewProcessTests}/Fakes/TestClock.swift`
remain as two unmodified copies on `main`. Nothing on the branch references `CellarTestSupport`.

**Archive classification: intentional-with-warnings.** Zero CRITICAL findings, zero blockers, so no
gate was overridden.

## Snapshot claims explicitly superseded by this report

| Snapshot claim | Source | Final state |
|---|---|---|
| "28/30 tasks complete" | `apply-progress` #7072 | **27 of 31.** The file has always held 31 boxes; the "30" total and "28" count were bookkeeping errors, flagged as WARNING 1 in `verify-report` |
| "7 phases / 30 tasks" | `tasks` index #7071 | **31 tasks.** The on-disk checklist is authoritative |
| "Branch … 12 commits, not pushed" | `tasks` index #7071 | Pushed and merged as PR #3; **11** commits after the rewrite |
| "Branch/head `feature/m2-catalog-hardening` @ `b321703` (13 commits off `main@cc373e8`)" | `verify-report` #7074 | Head no longer exists; see the mapping table above |
| "`explore.md` … removed again" | `apply-progress` #7072 | It was never removed from the *tree*; it was untracked, and the rewrite removed its churn from history. It remains **untracked on disk** and belongs to the future `m2-mutations-installed` (M2-1) change |
| "Next: `sdd-apply` again for Phase 5 … or `sdd-verify`" | `apply-progress` #7072 | Both happened: verify ran, PR #3 merged. Phase 5 is a follow-up, not an immediate next step |
| Verify verdict FAIL (initial run) | superseded `verify-report` revision | Superseded **in place** (Engram #7074 upserted) by the re-verification **PASS WITH WARNINGS**. Its single blocker — the stray `explore.md` in the tree — was remediated. The archive gate is satisfied by re-verification, not by an override |

## What shipped — six defects, all fixed

Numbering follows the proposal's verified-defect table, which is the M1 archive report's follow-up
register.

| # | Defect | Fix as delivered |
|---|---|---|
| 1 | `CatalogStore.adopt` built the ~16k-record `PackageSearchIndex` synchronously on `@MainActor`, violating M1 design D2 | `@concurrent public static func PackageSearchIndex.build(from:)` builds off-main; `adopt` became `async` and installs behind a monotonic **adoption ordinal**, so a slower older build is discarded rather than installed |
| 2 | `refreshNow()` adopted directly *and* through the `.snapshot` event — the index was built twice | New `CatalogSnapshotRevision` (a `Synchronization.Atomic` counter) gives a snapshot process-local identity, **pinned to the bytes on disk** so the 15-minute 304 poll cannot re-emit under a fresh identity. Duplicate adoptions are de-duplicated by revision; `refreshNow()` keeps its contract and its ingress |
| 3 | `CatalogSyncEngine.sync()` and `BrewDetectionStore.refresh()` cleared their single-flight slot only after the creator resumed, and `cancel()` never vacated it — a later caller joined settled or cancelled work and got a stale answer presented as fresh | Token-keyed slot with the `defer` **inside** the `Task` body, so the slot is empty before any joiner resumes. `cancel()` **marks and drains** rather than vacating, so the dying run's `defer { store.purgeStaging() }` cannot delete the successor's in-flight download. Applied at **both** sites — the exemplar `InstalledStore` will copy |
| 6 | Nothing stopped a zero-package snapshot being persisted as success | Write refusal → `failed(.malformedPayload)`, no `catalog.json` and no sidecar written, last good catalog still served. Delivered by the `CatalogFileStore.persist` guard (placed outside the `do` block that rewrites throws to `.persistence`) plus M1's per-resource decoder guard |
| 7 | A persisted zero-package snapshot decoded fine, so `revalidatable` stayed true, the origin answered 304, and the machine stayed empty forever | `loadSnapshot()` returns `nil` for a zero-package snapshot — the same answer as missing / corrupt / newer-schema — which routes into M1's existing CS6 path and forces an **unconditional** re-download (no `If-Modified-Since`, no `If-None-Match`). The poisoned file is left in place; a read path must not mutate the store |
| 10 | Both `TestClock` copies parked on a bare `CheckedContinuation` and never observed cancellation | **NOT DELIVERED** — Phase 5 cut. See follow-up #3 |

Also delivered, not in the design's File Changes table:

- **`.heavyFixture` cross-suite trait.** M1's `CatalogMemoryTests` asserts a budget on *process*
  `phys_footprint`, and this change's spec-mandated 15,000/15,500-record fixtures live in four suites
  that Swift Testing runs concurrently — the decode budget was reading 44–78 MB of another suite's
  snapshot and failing ~25% of runs. `.serialized` cannot express cross-suite exclusion, so heavy
  tests now carry a `TestScoping` trait backed by an actor lock. **No assertion or budget was
  weakened.**
- **`CatalogSyncSupport.swift`** — the swiftlint-mandated pure move described above.
- Test fakes the design did not name: `Fakes/Gate.swift`, `Fakes/Recorder.swift`,
  `Fakes/HeavyFixtureLock.swift`.

**Scope guard (task 6.2), re-evaluated at close and true in every clause**: public API added is
exactly `CatalogSnapshotRevision`, `CatalogSnapshot.revision`, its explicit `init(from:)` and
`PackageSearchIndex.build(from:)`; `next()`, `ordinal` and `carrying(_:)` stay internal;
`currentSchemaVersion` is still 1 and the persisted JSON still carries exactly `schemaVersion`,
`generatedAt`, `skippedRecordCount`, `packages`; nothing from follow-ups #4/#5/#8/#9; no M2 feature
work present.

### Documented deviations from design

1. **`adopt`'s duplicate joins rather than drops.** D2 said de-duplicate by identity, but the spec
   also requires `refreshNow()` to return "once the resulting snapshot is queryable". If the event
   stream claims the revision first, a *dropping* guard lets `refreshNow()` return before the index
   exists — caught as a flaky `laterSyncReplacesResults`. The duplicate now awaits the in-flight
   adoption task; `[weak self]` plus clearing the slot keeps it cycle-free. Verification judged the
   deviation justified, leak-free, race-free and deadlock-free.
2. **`adopt` and two instrumentation counters are `internal`, not `private`** — the design was silent
   on visibility, and ordering / dedup / off-main behaviour is unobservable from the public surface.
3. **Tasks 3.2, 3.4, 4.3, 4.4, 4.5, 4.6 were green on arrival** (as the design predicted for 3.2 and
   4.6). Verification confirmed all six can genuinely fail — 3.4 carries an explicit anti-ghost guard
   and 4.6's `validators == nil` is non-vacuous via the companion `unchangedSourcesRevalidateOnly`.
4. **Exactly one M1 assertion changed**, citing defect #1: `CatalogStoreTests.coldLaunchIsNonBlocking`
   now polls for `.succeeded` rather than reading it the instant results appear, because the engine
   yields `.snapshot` before `.succeeded` and adoption is now an `await`. Same assertion, polled. No
   `packages: []` convenience fixture existed anywhere, so the D6 fixture migration was a no-op.

## Specs merged (source of truth updated)

| Domain | Action | Details |
|---|---|---|
| `catalog-sync` | **Extended** `openspec/specs/catalog-sync/spec.md` | **4 ADDED** requirements / 13 scenarios appended verbatim; 0 modified, 0 removed. 9 / 26 → **13 requirements / 39 scenarios** |
| `package-search` | **Extended** `openspec/specs/package-search/spec.md` | **1 ADDED** requirement / 3 scenarios appended verbatim; 0 modified, 0 removed. 6 / 16 → **7 requirements / 19 scenarios** |
| `brew-detection` | **Amended** `openspec/specs/brew-detection/spec.md` | **1 MODIFIED** requirement — "Detection is observable, re-evaluated state" gained the single-flight clause; its 3 existing scenarios preserved byte-for-byte and 3 added. 5 / 12 → **5 requirements / 15 scenarios** |

Merge method, following the M1 precedent: requirement and scenario text copied **verbatim** from the
delta files; the delta-only `(Previously: …)` annotation was dropped from the requirement body and its
substance recorded in `## Provenance` instead; every requirement not named in a delta was left
untouched. The main specs carry no requirement-count header, so counts live in the provenance
bullets, which were updated with the new totals.

Three implementation notes were recorded in provenance rather than as spec edits, because in each
case the requirement text was already correct and the gap is in the code or in the archived
design/tasks:

- `catalog-sync` "A zero-package catalog is never published as success" — the engine-side semantic
  guard named in design D4 / tasks 4.x was **not** separately implemented; the refusal is carried by
  the file-store structural guard plus M1's decoder guard. All four scenarios are COMPLIANT, so this
  is design/tasks drift, not a spec gap.
- `catalog-sync` "A persisted zero-package snapshot is treated as no cache" — recovery is reached
  through the existing freshness path, so a poisoned snapshot beside a *fresh* sidecar stays silent
  until the staleness window passes.
- `package-search` "Index construction never runs on the main actor" — the latency test builds via
  the synchronous initialiser that the `@concurrent` factory wraps; compliance is transitive and
  proven by a companion equivalence test.

The `brew-detection` provenance also records the **pre-existing** `configuredPath` `didSet` stale-join
gap as explicitly out of scope for the merged requirement, routed to `m2-installed-inventory`.

## Artifact traceability

| Artifact | Engram observation | OpenSpec file (archived) |
|---|---|---|
| explore (source) | `#7064` `sdd/m2-mutations-installed/explore` | not this change — `openspec/changes/m2-mutations-installed/explore.md`, still untracked |
| M2 slicing decision | `#7065` | (Engram only) |
| proposal | `#7066` `sdd/m2-catalog-hardening/proposal` | `proposal.md` |
| proposal question round (Q1–Q4 settled) | `#7067` | (Engram only) |
| spec (3 deltas) | `#7068` `sdd/m2-catalog-hardening/spec` | `specs/{catalog-sync,brew-detection,package-search}/spec.md` |
| design | `#7069` `sdd/m2-catalog-hardening/design` | `design.md` |
| spec↔design reconciliation (mark-and-drain amendment) | `#7070` | (Engram only) |
| tasks | `#7071` `sdd/m2-catalog-hardening/tasks` — **stale counts, superseded by this report** | `tasks.md` (authoritative checklist) |
| apply-progress | `#7072` `sdd/m2-catalog-hardening/apply-progress` — **stale counts and commit hashes, superseded by this report** | (Engram only) |
| apply settlement (`size:exception`) | `#7073` | (Engram only) |
| verify-report | `#7074` `sdd/m2-catalog-hardening/verify-report` — re-verification, upserted in place over the initial FAIL | `verify-report.md` |
| delivery | `#7075` `sdd/m2-catalog-hardening/delivery` | (Engram only) — source of the review lineages and gate lessons |
| archive-report | `sdd/m2-catalog-hardening/archive-report` | this file |

No `sdd/m2-catalog-hardening/review/{transaction,ledger,receipt,gate-context}` Engram topics exist;
review authority was read from the repository CAS receipt for lineage `review-93ca396315542808`.

Verification evidence: `evidence_revision`
`sha256:8964a2fa1543a5db075248cd88a8381d5e8a85f15dacce1850a883518dcf3e78`;
`test_output_hash sha256:8605570f…`; `build_output_hash sha256:8b6b4993…`; `verify-report.md`
`sha256:5f18657d329756cf8f5537e9d99d1ec4880afaaf5ae381773ad316c0340a97d9`, admitted by
`gentle-ai sdd-verify-validate --requirements 6 --scenarios 22` before any write.

## Follow-up register (8 open, none blocking)

Carried forward for future M2 slices. Items 1 and 2 are routed to `m2-installed-inventory`, which
copies the exemplars they concern.

| # | Follow-up | Source | Routed to |
|---|---|---|---|
| 1 | **Adoption ordinal stamps on call arrival, not snapshot recency.** `adoptionSequence` is stamped on entry, so the last caller to *enter* wins. An `adopt` carrying an *older* snapshot that begins after a newer one was claimed would take a higher ordinal and install over the newer catalog. Unreachable in the tested and production ingress ordering (it needs a full second sync inside one ~30 ms index build). `CatalogSnapshotRevision.ordinal` is already a monotonic materialization counter, so guarding on it closes this in **one line** | verify WARNING 2 | `m2-installed-inventory` (copies the recipe) |
| 2 | **`BrewDetectionStore.configuredPath` `didSet` joins a probe started under the previous path** — pre-existing, not caused by this change. Fix is a path-keyed single-flight slot; the archived `design.md` already documents it as a deferred open question | design open question + review WARNING | `m2-installed-inventory` |
| 3 | **Phase 5: `CellarTestSupport` extraction + cancellation-aware `TestClock`** (design D5, defect #10). Both `Fakes/TestClock.swift` copies still park on a bare `CheckedContinuation`, so a cancelled test can hang instead of failing fast. Still owed | cut at apply | its own follow-up PR |
| 4 | **`CatalogAdoptionTests.swift:182` watcher loop is unbounded** and the suite carries no `.timeLimit` — a failure can hang `swift test` | review WARNING | unassigned |
| 5 | **Poisoned-snapshot recovery only triggers once the freshness sidecar goes stale.** A poisoned snapshot beside a fresh sidecar leaves an empty, silent catalog until the staleness window passes | review WARNING | unassigned |
| 6 | **Engine-side zero-package guard named in design D4 / tasks 4.x was not delivered.** The spec requirement is satisfied by the file-store guard plus M1's decoder guard, so this is design/tasks drift: either implement it in a follow-up or amend the archived design note | review SUGGESTION | unassigned |
| 7 | **Latency test builds via the synchronous initialiser** rather than the `@concurrent` factory (equivalence proven by a companion test); **design and proposal File Changes tables still list the cut Phase 5 artifacts** | review SUGGESTIONs | unassigned |
| 8 | **Prior M1 register items still open**: #4/#5 (payload size cap enforced only after the full download; `CatalogRefreshPolicy.payloadByteLimit` unwired) remain **deferred**; #8/#9 (refresh-loop / scene ownership, event-stream reattach) remain routed to `m2-installed-inventory` | M1 archive report | #4/#5 deferred, #8/#9 → `m2-installed-inventory` |

M1 register items **#1, #2, #3, #6, #7** are **closed by this change**. Item **#10** is follow-up #3
above.

Minor, unclassified: the stale comment in `lateOlderAdoptionIsDiscarded` says "`older` is 15,500
records" while the code uses 8,000 (verify SUGGESTION 1).

## Archive integrity

- Change folder moved to `openspec/changes/archive/2026-08-02-m2-catalog-hardening/` with `git mv`,
  byte-preserving. Phase artifacts (`proposal.md`, `design.md`, `tasks.md`, `specs/`) are untouched;
  only this report was added.
- `verify-report.md` was untracked at close (it was written after the branch was frozen for review)
  and is committed as part of the archive commit, following the M1 precedent.
- `openspec/changes/m2-mutations-installed/explore.md` stays **untracked** — it belongs to the future
  M2-1 change and will be committed under that change's own proposal.
- `tasks.md` retains its 4 unchecked Phase 5 boxes and its deferral note; no checkbox was altered at
  archive time. See "Intentional partial archive".
- `verify-report.md` and `apply-progress` (#7072) cite commit hashes that no longer exist. The
  mapping table near the top of this report is the bridge; the content they verified is preserved
  byte-identically as tree `504f956`.

## Next

`m2-installed-inventory` — M2 slice **M2-1**, which introduces `InstalledStore` and copies the
single-flight and adoption recipes hardened here, and which carries follow-ups #1, #2 and M1's #8/#9.
