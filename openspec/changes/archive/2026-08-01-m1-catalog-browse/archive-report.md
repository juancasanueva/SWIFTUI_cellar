# Archive report: m1-catalog-browse

**Change**: `m1-catalog-browse` — M1 (PRD milestone "Core & Catalog", second and final slice:
catalog sync, package search, package detail, Browse UI). Closes the M1 exit criterion "search 14k
packages instantly, view any package's full details".
**Closed**: 2026-08-01 · **Artifact store**: hybrid (OpenSpec files + Engram, project `cellar`)
**Status at close**: shipped and merged to `main`. SDD cycle complete.

This report is the terminal record of the cycle. Where it disagrees with `apply-progress` or
`verify-report`, those are intermediate snapshots and this report states the final state.

## Final state

| Fact | Value at close |
|---|---|
| Delivery | Single PR **#2** (`feature/m1-catalog-browse` → `main`), **merged by the user** |
| Merge commit | `de83c13` on `main`, containing all **13** change commits |
| Local `main` | synced with `origin/main` |
| Tasks | 71/71 complete, all `[x]` in the archived `tasks.md` (0 unchecked; no reconciliation needed) |
| Tests (package) | **214/214** in 33 suites — `swift test --package-path Packages/CellarCore` |
| Tests (release latency gate) | **2/2** — p95 **1.02 ms** against the 8 ms ceiling |
| Tests (app scheme) | `xcodebuild test … -skip-testing:cellarUITests` → `** TEST SUCCEEDED **` |
| Verify verdict | **PASS WITH WARNINGS** — 0 blockers, 0 critical, 2 warnings, 3 suggestions |
| Requirements / scenarios | 21/21 requirements, 59/59 scenarios COMPLIANT (0 PARTIAL, 0 UNTESTED) |
| Post-verify review | native review found **2 CRITICAL**, both fixed and independently validated (below) |
| Authored diff | ~7.6k authored lines (review measured **8,622** total changed lines) |
| Delivery strategy | `single-pr` with user-accepted `size:exception`, **re-confirmed twice** |

`cellarUITests` is excluded from the app gate by a pre-existing template failure ("Failed to activate
application … Running Background") that reproduces identically on `main`. `git diff main...HEAD`
touches zero files under `cellarUITests/`; the change never modified it.

### Snapshot deltas explicitly superseded by this report

| Snapshot claim | Source | Final state |
|---|---|---|
| "Not pushed, no PR opened" | `apply-progress` #7055 | PR #2 opened and merged as `de83c13` |
| "9 conventional commits, not pushed" | `tasks` #7054 | 13 commits, merged |
| "Branch HEAD `1c5331c`, 11 commits" | `verify-report` #7056 | 13 commits; final work landed in `b9077c5` and `6ef84f0` |
| "FAST 212/212" | `verify-report` #7056 (true at `1c5331c`) | **214/214** — the correction added two regression tests |
| "No CRITICAL issues remain open" | `verify-report` #7056 (true at verification time) | Two CRITICALs were found *after* verification by the native review; both are fixed and validated, so the statement holds at close but not for the reason the snapshot gives |
| WARNING-1: `apply-progress` test-count attribution wrong | `verify-report` #7056 | Corrected below; see "Verify warnings at close" |

The first verification run FAILED on one CRITICAL (a tautological assertion,
`#expect(x.isEmpty == false || x.isEmpty)`, in `ProjectionTests.swift:136`). It was fixed test-only
in `1c5331c` and the re-verification PASSED WITH WARNINGS, superseding the FAIL. The archive gate is
satisfied by the re-verification, not by an override.

## Post-verify correction story (final state not captured in `verify-report.md`)

The native branch review ran **after** `sdd-verify` and found two CRITICAL defects that the
verification gates had not exercised. Both were fixed inside a single bounded correction transaction
and independently validated. `verify-report.md` predates all of this.

**Lineage** `review-c71698f49010e184` · receipt at
`.git/gentle-ai/review-transactions/v2/review-c71698f49010e184/review-receipt.json`.

### CRITICAL 1 — `R3-revalidated-sync-persists-empty-catalog`

A `304` revalidation whose backing snapshot could not be read persisted an **empty catalog and
reported success** — an unreadable cache was treated as an empty valid cache instead of as "no
cache". A user hitting this once would see an empty Browse list that never recovers, because the
next sync also revalidates.

Fixed in **`b9077c5`**: `acquirePayloads` gained a `revalidatable` flag so a source is only
revalidated when a readable snapshot actually backs it; otherwise the request goes out
unconditionally. Regression test added.

This is exactly what `catalog-sync` already mandated ("a sidecar … MUST be treated as no cache";
"an unchanged response MUST keep the existing snapshot"). **No requirement text was changed** — a
provenance note recording the fix as implementation evidence was added to
`openspec/specs/catalog-sync/spec.md`.

### CRITICAL 2 — `R3-second-window-duplicate-event-stream-consumer`

Opening a second window double-consumed the single-consumer event stream — a classic
`AsyncStream` single-subscription trap: the second consumer silently steals events from the first.

Fixed in **`b9077c5`**: `CatalogStore.start()` gained an `isRunning` guard so a second `start()` is a
no-op instead of a second consumer. Regression test added.

### Deflake and validation

The new regression test was itself flaky — the validator measured **3 of 7 runs failing before the
fix**. It was deflaked in **`6ef84f0`**, after which **14/14 runs were green**. Targeted validation
then passed, consuming **76 of the 200** available correction lines.

Receipt state at close: `terminal_state: approved`, `evidence_outcome: passed`,
`resolved_finding_ids: [R3-revalidated-sync-persists-empty-catalog,
R3-second-window-duplicate-event-stream-consumer]`, `risk_level: medium`, lens `review-reliability`,
generation 1, base tree `7173febb…`, final candidate tree `5111c2d8…`, non-empty `fix_delta_hash`
(one correction transaction consumed). Delivery gates `post-apply` / `pre-commit` / `pre-push` /
`pre-pr` all returned **allow**.

Archive gate: satisfied by `reviewGate.result: allow` with the approved terminal receipt read and
matched to the final candidate tree.

## Specs merged (source of truth updated)

| Domain | Action | Details |
|---|---|---|
| `catalog-sync` | **Created** `openspec/specs/catalog-sync/spec.md` | 9 requirements / 26 scenarios ADDED, 0 modified, 0 removed |
| `package-search` | **Created** `openspec/specs/package-search/spec.md` | 6 requirements / 16 scenarios ADDED, 0 modified, 0 removed |
| `package-detail` | **Created** `openspec/specs/package-detail/spec.md` | 6 requirements / 17 scenarios ADDED, 0 modified, 0 removed |
| `brew-execution` | **Already applied during apply** (task 10.1) | 1 MODIFIED requirement, 2 scenarios carried verbatim — **not re-applied at archive** |
| `brew-detection` | **Already applied during apply** (task 10.2) | 1 MODIFIED requirement, 3 scenarios (1 amended THEN block) — **not re-applied at archive** |

All three new capabilities had no prior main spec, so each delta was ADDED-only and became the first
main spec for its capability. Requirement and scenario text was copied verbatim; only the file
header, the `## Requirements` wrapper, and a `## Provenance` section were added.

**Editorial deltas verified, not re-applied.** Tasks 10.1 and 10.2 applied the two MODIFIED
requirements to `openspec/specs/` during apply, and they landed inside merged PR #2. Verified at
archive by reading both main specs: each carries an
`**Editorial reconciliation (change m1-catalog-browse, 2026-08-01)**` provenance bullet, and the
requirement bodies match the delta text (`brew-execution` "Terminal result and exit handling" now
enumerates four terminal outcomes and names the two that are errors; `brew-detection` "Disappearing
configured path transitions away" now states `configuredPathMissing` as the single THEN outcome with
`invalid(notExecutable)` as the contrasting AND clause). Re-applying would have been a no-op at best
and a duplication at worst, so nothing was changed in either file during this archive.

### CS6 provenance decision

The `catalog-sync` requirement "Slim persisted projection with a state sidecar" (CS6) mandates that
an unusable sidecar be "treated as no cache". `b9077c5` implements exactly that for the unreadable
snapshot path. **Decision: record it as a provenance note, do not touch the requirement text.** The
requirement was already correct — the code diverged from it, not the other way round — so amending
the spec would falsify the audit trail by making a code defect look like a spec gap. The note names
the finding ID, the fix commit, and the approved receipt as implementation evidence.

## Artifact traceability

| Artifact | Engram observation | OpenSpec file (archived) |
|---|---|---|
| explore | `#7050` `sdd/m1-catalog-browse/explore` | (Engram only) |
| proposal | `#7051` `sdd/m1-catalog-browse/proposal` | `proposal.md` |
| spec (5 deltas) | `#7052` `sdd/m1-catalog-browse/spec` | `specs/{catalog-sync,package-search,package-detail,brew-execution,brew-detection}/spec.md` |
| design | `#7053` `sdd/m1-catalog-browse/design` | `design.md` |
| tasks | `#7054` `sdd/m1-catalog-browse/tasks` | `tasks.md` |
| apply-progress | `#7055` `sdd/m1-catalog-browse/apply-progress` | (Engram only) |
| verify-report | `#7056` `sdd/m1-catalog-browse/verify-report` | `verify-report.md` |
| delivery | `#7057` `sdd/m1-catalog-browse/delivery` | (Engram only) — source of the follow-up register below |
| archive-report | `sdd/m1-catalog-browse/archive-report` | this file |

No `sdd/m1-catalog-browse/review/{transaction,ledger,receipt,gate-context}` Engram topics exist for
this change; review authority was read directly from the repository CAS receipt listed above.

Verification evidence hashes (from the admitted `gentle-ai.verify-result/v1` block):
`evidence_revision sha256:0f201710…`, `test_output_hash sha256:e5dfb8ee…`,
`build_output_hash sha256:367bca62…`. `verify-report.md` itself is
`sha256:fd6ebc5db5f7026f7d3c0300033886c0cc75ebb091f03bc946a4b1aa2dee0beb` (329 lines), admitted by
`gentle-ai sdd-verify-validate --requirements 21 --scenarios 59` before any write.

## What shipped

- **`Catalog` library target** in `Packages/CellarCore` (Swift 6 language mode, no `BrewProcess`
  dependency): tolerant wire decoding (cask `name` arrays, null `desc`/`caveats`, String-or-Object
  `uses_from_macos`, unknown keys, `LossyArray` skip-and-count, zero-record guard), slim projection
  with a state sidecar, `CatalogFileStore` with atomic `replaceItemAt` full-replace persistence, and
  a `CatalogSyncEngine` actor doing conditional revalidation, backoff retry (transport/429/5xx only),
  staging purge on every outcome, and a poll-and-compare 24 h freshness loop.
- **Search**: `PackageText` POSIX-locale ASCII folding, `PackageSearchIndex` struct-of-arrays,
  one-pass four-bucket ranking with lazy best-first sort and a total order
  `(rank, count desc, name, formula<cask)`.
- **Detail**: full PD1 projection, flat direct dependency lists with link-time `isResolvable`,
  dependents by sync-time edge inversion over build and runtime edges, independent
  deprecation/disabled statuses with reasons and dates, install count as an opt-in 365-day lower
  bound.
- **`@MainActor @Observable CatalogStore`** façade: cache load, `isReady`, structured task group for
  the event observer and refresh loop, synchronous rerank on `query`/`filters`, single-flight
  `refreshNow()`.
- **Browse UI**: `NavigationSplitView` shell, `BrowseView` / `PackageRow` / `CatalogFilterBar` /
  `PackageDetailView` / `SyncBanner`, `cellarApp` owning the store with the SwiftData `ModelContainer`
  and `Item.swift` removed. UI copy lives in `Catalog/CatalogPresentation.swift` as tested pure
  functions.
- **Xcode link**: four `project.pbxproj` hunks in one commit plus the `CellarCore.xcscheme` build and
  testable entries for `Catalog` / `CatalogTests`.

Live integration measured at apply time: cold sync 2.56 s, 16,200 records, 0 skipped, peak footprint
Δ **177.2 MB**, `catalog.json` 7,114,578 B, staging purged; revalidation sync 0.158 s with no body
transferred. Slim-projection ratio 47,795,814 B in → 6,862,330 B (**7.0x**).

## Follow-up register (carried from Engram `sdd/m1-catalog-browse/delivery` #7057)

None blocking; none is a shipped-behaviour regression. Ordered roughly by user-visible impact.

| # | Follow-up | Why it matters |
|---|---|---|
| 1 | Main-actor index rebuild blocks the UI | ~16k records rebuilt on the main actor; violates the design D2 claim that the rebuild stays off the main actor |
| 2 | `refreshNow()` double-adopts the snapshot | The index is built twice for one refresh — wasted work on the hot path |
| 3 | `CatalogSyncEngine` single-flight can join a finished or cancelled task | Same defect class as the known `BrewDetectionStore` stale-join follow-up |
| 4 | Payload size cap enforced only after the full download | The 128 MB `payloadTooLarge` guard fires after the bytes are already on disk |
| 5 | `CatalogRefreshPolicy.payloadByteLimit` is unwired | The declared limit has no effect; dead configuration |
| 6 | No defence-in-depth against an empty snapshot | A non-conformant origin could still make an empty snapshot persistable as success — `b9077c5` closed the revalidation path, not the general one |
| 7 | A zero-package snapshot poisoned before the fix has no recovery path | Should be treated as "no cache" on load rather than served as an empty catalog |
| 8 | Refresh-loop ownership dies when the owning window closes | With other windows still open, background refresh stops until a new owner starts |
| 9 | Event-stream reattach doubt | `b9077c5` stops the *second* consumer; whether a legitimate reattach after `stop()` works is untested |
| 10 | `TestClock` ignores cancellation (both copies) | `Tests/CatalogTests/Fakes/TestClock.swift` and the `BrewProcessTests` original; a cancelled test can hang instead of failing fast |

## Verify warnings at close (2 open, neither blocking)

1. **`apply-progress` test-count attribution — corrected here.** `apply-progress` #7055 claims "212
   in the Catalog module … 117 for BrewProcess". The gate total was right, the split was not:
   re-measured at verification time there were **126** `@Test` declarations in `CatalogTests` and
   **86** in `BrewProcessTests` = the 212 the FAST gate reported for the whole package. At close the
   package total is **214**; the two added tests are the `b9077c5` Catalog regression tests, so the
   expected split is 128/86 — *derived from where the fix landed, not re-measured*. Treat 214 as
   measured and the split as inferred.
2. **`CatalogMemoryTests.swift:144` — redundant `nonisolated(unsafe) let shared = self`.** Still
   present. The invariant holds (`Sampler` is a `final class`, `Sendable`, mutable state behind a
   `Mutex`), so the annotation is redundant rather than unsafe. It should either carry a documented
   safety invariant or be deleted. Test-only.

Suggestions carried forward unchanged: (S1) `CatalogFileStore.persistState` and
`DefaultCatalogFileSystem.replaceItem` have no direct covering test, both exercised transitively;
(S2) a `.swiftlint.yml` would silence the template-inherited findings and the spec-mandated
`succeeded(at:)` label; (S3) the origin emits **weak** ETags (`W/"…"`) — harmless as shipped, matters
only if byte-range or strong-comparison logic is ever added.

## Deviations (all re-confirmed spec-conformant)

`syncStatus` over the design draft's `syncState`; `excludeDeprecated`/`excludeDisabled` over
`includeDeprecated`; UI copy extracted to `CatalogPresentation.swift`; deprecation/disable dates
gated on the flag so a *scheduled* disable date is not reported as disabled; computed `InstallCount`;
link-time `isResolvable`; `payloadTooLarge` surfaced as `.malformedPayload`; analytics fetch not
retried. Design `CatalogError`/`CatalogSyncState` were reconciled to the spec's
`CatalogSyncError`/`CatalogSyncStatus` — spec names win.

## Archive integrity note

The archived change folder is an audit trail: `proposal.md`, `design.md`, `tasks.md`,
`verify-report.md`, and `specs/` are preserved byte-for-byte as written by their phases. Only this
report was added. In particular, `verify-report.md` still describes the branch at `1c5331c` and
still says 212 tests — that was true when written; this report states the final state.

The archived `tasks.md` contains no unchecked implementation tasks; no stale-checkbox reconciliation
was needed or performed.
