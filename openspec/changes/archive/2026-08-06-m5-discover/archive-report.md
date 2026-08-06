# Archive Report: M5 Discover

`m5-discover` closed **slice 2 of 5** of PRD milestone **M5 "Pro-parity flows"** on 2026-08-06. The
change **added one new capability** (`package-discovery`), modified one shipped capability
(`catalog-sync`), added no new target, product or dependency edge, passed independent verification
with zero CRITICAL findings, merged to `main` as PR #17, and moved to the dated OpenSpec archive.

**M5 is not closed by this archive.** Three slices remain active: `m5-release-notes`, `m5-brewfile`,
`m5-health`. The shared exploration `openspec/changes/m5-pro-parity/explore.md` serves all five and
stays in the active changes directory until M5 completes.

The defining result of the slice is that **verification found a real gap and the cycle was honest
about it**. `sdd-verify` returned **fail** on its first pass over a candidate whose production code
was already correct: `catalog-sync` CS-A2 scenario 3's *write* half — that an expired arrival is
actually removed from the file — was unobserved, because every existing arrivals assertion read
through a path that prunes on read and would therefore mask a missing write-side prune. One 62-line
test closed it, and a mutation check proved the test has teeth. **No production line changed.** The
second verify pass returned **pass**. That sequence is recorded below in full, because a cycle that
reports the gap it found is worth more than one that reports a clean first pass.

## Closure Status

| Check | Final state |
|---|---|
| Requirements | 10/10 COMPLIANT (4 `catalog-sync`, 6 `package-discovery`) |
| Scenarios | 46/46 COMPLIANT — zero UNTESTED, FAILING or PARTIAL |
| Tasks | 52/52 checked in the archived `tasks.md`; zero unchecked; no reconciliation needed or authorized |
| Verification | **PASS on re-verify** — 0 CRITICAL, 3 WARNING, 6 SUGGESTION (first verdict **fail**, 1 CRITICAL, remediated — see below) |
| Work units | `apply-batch-1` → `passed`; `verify-1` → **failed** (honest coverage gap); `apply-remediation-cs-a2-sc3` → `passed`, linked by `--remediates-evidence-revision`; `verify-2` → `passed`. All settled. |
| Delivery | Merged to `main` as **PR #17** at `d068cdc` (2026-08-06); branch `feature/m5-discover` |
| Delivery policy | Receipt-driven development **off, clone-local**; ordinary repository policy |
| Review authority | **No receipt exists for this candidate** — see *Delivery Record* |
| Size policy | `single-pr`, no `size:exception`; ~4,457 authored lines inside the 5,000-line session budget |

`reviewGate` is structurally absent because the review kill switch is off for this clone. There is no
`disabled/unmanaged` value to check and no receipt was required, so archive proceeds under ordinary
repository policy. Nothing was silently approved: the green gates and the verify report below are the
evidence standing in place of a receipt. No review tooling was invoked at any phase of this change.

## Scope Shipped

**NEW capability `package-discovery`** — 6 requirements / 23 scenarios, ADDED-only. It owns what
Discover *shows* and none of the durable state those projections read.

- *Two separate ladders, fifty deep, absent is not zero* (6 scenarios) — formulae rank on
  `installsOnRequest`, casks on `installs`, never merged; ≤50 each; an absent `installCount365d` is
  **ineligible**, never rank-last and never coerced to `0`; deprecated and disabled are ineligible;
  short ladders are never padded; ties order deterministically; carried-forward counts still rank.
- *Discover costs no new acquisition* (2 scenarios) — zero requests, zero `brew` spawns, no sync
  triggered by a section rendering.
- *The curated list ships with the build and decodes tolerantly* (4 scenarios) — loaded through the
  shipping accessor with no network; an entry is token + category + blurb, and a blurb never falls
  back to the package's own `desc`; unknown keys ignored; duplicate token → first declaration wins
  and the redundant one is counted; declared order preserved; 3–5 categories / 20–30 entries asserted
  over the **shipped** resource.
- *A curated entry that no longer resolves is skipped and counted* (4 scenarios) — resolved by
  `(kind, name)`; unresolved entries are skipped, counted and never a dead row; the count is `0`
  rather than absent when clean; **distinct** from the snapshot's own `skippedRecordCount`; a
  fully-skipped category disappears rather than rendering empty.
- *New to you means first observed by this machine, within 30 days* (4 scenarios) — projected from
  the arrivals log only, never a publication date; entries carry their first-observed date, newest
  first; entries absent from the snapshot are not projected. **The honest phrasing is a requirement**:
  `CellarCore` supplies the copy, it says *first seen by this Mac*, and it must not claim newly
  released or new to Homebrew.
- *Every section reports a typed state, and Discover never opens empty* (3 scenarios) — typed
  populated / empty-with-named-reason, never an empty collection paired with an empty string, never a
  failure, never pending when the catalog is available; arrivals is the only ordinarily-empty section
  and carries the "measured from this sync onward" identity; no all-empty-unexplained result; no
  snapshot means awaiting-catalog, not error.

**MODIFIED `catalog-sync`** — 2 requirements replaced as whole blocks, 2 requirements added.

- *Slim persisted projection with a state sidecar* (6 → 9 scenarios) — the version gate broadens from
  two named files to **every file the catalog persists**, gains "nor rejected on the strength of
  another's version", and admits an additional file that adds no projection field, gated against **the
  version its own owning schema declares**. Independence is stated in **both** directions. The
  footprint bound is pinned to the snapshot **alone** and must not be re-based.
- *Inspection data costs no new acquisition* (2 → 3 scenarios) — the persisted-artefact enumeration
  widens from two files to exactly four; deriving newness locally introduces no request.
- **ADDED** *A durable known-package roster records what this machine has already seen* (6 scenarios).
- **ADDED** *The dated arrivals log retains thirty days and prunes itself* (5 scenarios).

**New capabilities:** one (`package-discovery`). **New targets, products or dependency edges:** none
— the only `Package.swift` change is a single `resources: [.copy("Discovery")]` line on the existing
`Catalog` target, and `project.pbxproj` was never edited because `cellar/Discover/` is a
`PBXFileSystemSynchronizedRootGroup` (a **0-line** pbxproj diff, confirmed by measurement).

**Not shipped, deliberately**: any new network call, endpoint or credential; any change to Browse
search, filters or ranking; editorial content beyond a v1 seed list; **any new field on
`CatalogPackage`**; any change to `CatalogSnapshot`'s shape or `schemaVersion`; release notes
(slice 3), Brewfile (slice 4), the health dashboard and bulk polish (slice 5).

## Specs Synced

| Domain | Action | Result |
|---|---|---|
| `package-discovery` | **Created** | New main spec at `openspec/specs/package-discovery/spec.md`. **6 requirements / 23 scenarios**, promoted byte-identical from the delta. The file adds only the `# package-discovery` header, the `## Requirements` wrapper and a provenance section. |
| `catalog-sync` | **Updated** | 2 requirements replaced as whole blocks, 2 appended. 14 requirements / 51 scenarios → **16 requirements / 66 scenarios** (measured from the installed file). The other twelve requirements are byte-identical. |

### Scenario-count reconciliation (measured vs projected)

The spec observation (#7494) projected `catalog-sync` at **16 requirements / 66 scenarios** after the
merge. The merge was measured directly from the installed file and yields **16 / 66** — the
projection was exactly right this time. This is recorded because slice 1 taught the opposite lesson:
its forward projection of merged scenario totals was arithmetically low (14/49 projected against
14/51 measured), so the projection is checked against measurement rather than trusted. The arithmetic:
51 − 6 − 2 replaced + 9 + 3 in the MODIFIED blocks + 11 ADDED = **66**.

`package-discovery` measures **6 / 23**, matching its ADDED-only delta exactly.

### Destructive-delta check (required by `openspec/config.yaml` `rules.archive`)

**Nothing was removed and nothing was renamed** — neither delta carries a `## REMOVED Requirements`
or `## RENAMED Requirements` section, and **zero requirements and zero scenarios were deleted** by
the merge. Each MODIFIED block was diffed against the text it replaced:

- *Slim persisted projection with a state sidecar* — **10 changed lines, all broadening or
  annotation.** Four lines of the version-gate paragraph were rewritten from "**both** persisted
  files — the snapshot and the state sidecar — so neither can be adopted on the strength of the
  other's version" to "**every file the catalog persists** … so no file can be adopted on the
  strength of another's version, **nor rejected** on the strength of another's version": strictly
  more files bound and strictly more forbidden. Two lines carrying "Classification MUST NOT throw,
  MUST NOT be reported through a failure status, and MUST NOT mutate or delete the file it rejected"
  were re-wrapped with new text inserted before them — **the sentence itself survives verbatim**. One
  line ("retained.") was extended with the snapshot-alone footprint rule. The remaining three lines
  are the requirement's non-normative `(Previously: …)` annotation, replaced by a new one describing
  this slice's change; the superseded annotation is preserved in the archived slice-1 delta and in
  this main spec's provenance section. **All six pre-existing scenarios survive byte-for-byte**; three
  were appended.
- *Inspection data costs no new acquisition* — **2 changed lines, and the only genuine relaxation in
  this merge.** The persisted-artefact enumeration widened from "exactly the snapshot and its state
  sidecar" to exactly four files, once in the requirement body and once in the closing `AND` of the
  scenario *The widened sync issues no additional request*. This **relaxes a prohibition** rather than
  removing a guarantee: two additional files become permissible, and only those two. The zero-egress
  promise is untouched and is extended to newness explicitly. One pre-existing scenario is
  byte-identical, one has exactly the one edited line the delta header declared, and one was appended.

**No requirement or scenario was deleted, so the merge is not destructive and no confirmation was
required.** The check was run and is recorded here rather than assumed. The single relaxation is
called out by name in the merged spec's provenance section so a later reader meets it as a decision
rather than discovering it as a drift.

## The Verify Fail → Remediation → Pass Journey

This is the slice's carried lesson, recorded in sequence rather than collapsed into its outcome.

**verify-1 returned `fail`, 1 CRITICAL.** `catalog-sync` CS-A2 scenario 3 — *An entry beyond the
window is pruned on the next write* — has two halves: the **read** must yield only the in-window
entry, and the **file afterwards** must hold only the in-window entry. The read half was covered. The
write half was not observed by any test. Every arrivals assertion in the suite read through
`loadArrivals()` or `engine.arrivals()`, **both of which prune on read** — so a build that never
pruned on write would have passed the entire suite while growing an unbounded arrivals file on the
user's disk. Verify raised it as a blocker rather than a note, and that judgement was correct.

**The remediation was one test, not a code change.** `SyncEngineTests > An expired arrival is removed
from the file by the next write` (+62 lines) is the right shape on four counts:

- **It observes the file, not the projection** — raw `Data(contentsOf: store.arrivalsURL)`, never a
  pruning-on-read accessor. That was exactly the gap.
- **Positive control first** — it asserts `stalepkg` really is in the persisted bytes *before*
  asserting it is gone, so it proves a removal rather than a pre-existing absence.
- **It takes the diffing branch**, not the seeding branch, so it exercises the prune actually being
  policed.
- **It distinguishes pruning from truncation** — `sorted() == ["freshpkg", "newpkg"]` requires the
  in-window entry to survive *and* the new arrival to be recorded.

**Mutation-checked.** Removing `.pruned(now:)` from `DiscoveryRosterDiff.advance` makes exactly this
test fail — 3 assertions, matching the assertion count exactly — and **no other test in the suite**.
That independently confirms both that the test has teeth and that verify's finding was real. Every
other `advance` call site passes `nil`, `.empty`, a freshly-derived log or a 10-day-old entry, and
every engine-level arrivals assertion reads through a pruning path. The mutation was reverted; both
branches call `.pruned(now: now)`.

**Delta scope was independently confirmed.** `git diff --numstat` shows only `SyncEngineTests.swift`
moved (142 → 204 added lines, exactly +62). Every other tracked file is byte-count-identical to
verify-1 and untracked authored content is unchanged at 3,745 lines across 26 files. **No production
code changed** — the correct outcome, because the code was right and only the proof was missing.

**verify-2 returned `pass`** — 0 CRITICAL, 46/46 scenarios, admitted by
`gentle-ai sdd-verify-validate --requirements 10 --scenarios 46` (`valid: true, verdict: pass`),
evidence revision sha256 `fcc103c7…`. The archived `verify-report.md` records the full journey; the
Engram observation (#7499) was superseded in place, so its revision 2 is the pass and revision 1 was
the fail.

## Final Gates (measured at the merged candidate)

Every number below was re-measured by `sdd-verify` at the final candidate, not copied forward from
apply.

| Gate | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1213 tests / 162 suites passed**, 1 pre-existing known issue, 0 failures, exit 0 |
| `xcodebuild test -project cellar.xcodeproj -scheme cellar` (FULL, incl. XCUITest) | `** TEST SUCCEEDED **`, 23 UI cases, 56 `cellarTests`, 0 activation errors, exit 0 |
| `xcodebuild build -project cellar.xcodeproj -scheme cellar` | `** BUILD SUCCEEDED **`, **zero** warnings, exit 0 |
| Tasks | **52 checked / 0 unchecked**, counted from the archived file |
| Validator | `gentle-ai sdd-verify-validate --requirements 10 --scenarios 46` → `valid: true, verdict: pass` |

Baseline 1140 tests / 156 suites (slice 1's close) → **+73 tests, +6 suites**. The single known issue
is a deliberate `withKnownIssue` in `OperationCenterCancelTests`, an untouched suite —
**pre-existing and unchanged by this slice**, exactly as it was at slice 1's close.

**The frozen invariants held.** `CatalogFootprintTests` was re-run **unchanged** with a **zero-line
diff** rather than re-based; `CatalogPackage`'s stored-property set is unchanged;
`CatalogSnapshot.currentSchemaVersion` is still **2**; `CatalogModels.swift` and `project.pbxproj`
are untouched. All 25 curated tokens were re-verified live via `brew info --json=v2` as present, not
deprecated and not disabled. An assertion audit across 278 sites returned 0 CRITICAL / 0 WARNING.

## Delivery Record

- **Merged to `main` as PR #17** at `d068cdc` — from `feature/m5-discover`, carrying `556842b`
  *feat(catalog): discover tab with ladders, curated list and new-to-you* and `083da53`
  *docs(sdd): record the m5-discover lifecycle*.
- **Single PR, no size exception.** Forecast 2,000–2,900 authored source+tests; measured **≈4,457
  authored**, or **5,659 including lifecycle artifacts**. Above forecast and inside the 5,000-line
  session budget with ~540 lines of headroom. The overage is test density, not scope creep; the
  pre-agreed Phase 9 cut point (the app layer, presentation-only) was not needed.
- **Receipt-driven development: no receipt exists for this candidate.** The kill switch is off
  clone-locally, so zero review code ran and no review tooling was invoked at any phase. Delivery
  proceeded under ordinary repository policy. Recorded as fact, not as approval.
- **Rollback remains a single `git revert`.** One `resources:` line and one resource directory;
  `cellar/Discover/` is a synchronized root group so there is no target-membership, build-setting or
  scheme edit to unwind. `CatalogSnapshot` and `currentSchemaVersion` are untouched, so no cache is
  invalidated in either direction. Because the sidecars carry their **own** schema version, a reverted
  then re-applied slice **resumes** a user's existing 30-day arrivals history instead of reseeding it.

## Two Decisions That Shaped the Slice

1. **The revision ordinal cannot carry newness** (mechanism correction, Engram #7493).
   `CatalogSnapshotRevision` is documented as process-local and never persisted, so ordinals restart
   at 1 on every launch and a diff keyed on them would report the **entire catalog** as new on the
   second launch. The M5 decision round's "diff via revision ordinals" was therefore not implementable
   as stated. Newness needs a durable roster; the ordinal keeps its existing job in `adopt` and gains
   none. This was caught at proposal time, not at apply time.
2. **Independent sidecar versioning is user-protective, not stylistic** (design ADR, Engram #7495).
   Slice 1's hard constraint mandates the version-gate **idiom** — exact in both directions,
   absence-not-error, never mutating the file it rejects — not the shared constant. Keying the roster
   and arrivals log to `CatalogSnapshot.currentSchemaVersion` would let any unrelated projection bump
   silently erase a user's retained 30-day history, breaking the 30-day promise for a reason the user
   never caused. `DiscoverySchema` declares its own `currentVersion = 1`, and the spec states the
   independence in **both** directions.

Eight apply-time design amendments were recorded in `design.md` rather than silently absorbed, and
verify confirmed all eight consistent with the spec. Two are worth carrying: the design's flat
`DiscoverContent` field list did not name the typed per-section states PD-R6 requires (the spec
governs, and the tasks flagged it rather than absorbing it); and `cellarApp.swift`, which the design
said needed no change, took exactly one line — as a UI-test seam, not as wiring.

## Carried Follow-Ups

**None is a defect in what shipped.** All are recorded so they do not disappear with the slice.

1. **XCUITest transient host-focus flake — budget CI retries.** During re-verification, a full run
   exited 65 with **17 of 23 UI tests failing**, including M3/M4 tests this change never touches.
   Every failure was the identical XCTest infrastructure error — `Failed to activate application
   'com.juancasanueva.cellar' (current state: Running Background)` — each timing out at ~61.6 s.
   **Not one was an assertion failure**, and `cellarTests` was 56/56 even in the failed run. Proven
   non-reproducible rather than assumed: an immediate `-only-testing:cellarUITests` re-run passed
   23/23 in 204 s (against 1,112 s of timeouts), then a full re-run of the declared command passed
   23/23. **If CI meets this it will look like a catastrophic regression and is not one** — budget a
   retry or pin the runner's foreground state.
2. **The arrivals footprint bound has ~1 KB of headroom** (~63 KB measured against a 64 KB bound at
   the 1,000-entry cap). The measurement is a byte count, so this is brittleness rather than flake —
   but **a future field on `PackageArrival` breaks it**. Treat the bound as a gate to re-price
   against, not as a background invariant.
3. **Task 6.5's RED was never separately observed** — adjudicated as anchored, because the positive
   controls in that area make vacuous passing impossible. Recorded as a process observation, not as
   missing coverage.
4. **Slice-1 carry-over W2 — the decorative assertion is still present, re-checked at archive.**
   `AcquisitionScopeTests.swift` **was modified by this slice** (+80/−3), so the claim was verified
   rather than repeated: at lines 165–167 `offlineSource` is still built and scripted but never
   handed to anything, and line 190's `#expect(offlineSource.requests.isEmpty)` still asserts that an
   unused fake recorded nothing. The requirement it covers remains satisfied by the surrounding
   by-value assertions. The fix, when taken: delete the line, or wire the fake into a real sync
   attempt so it can fail.
5. **Slice-1 carry-over S4 — the encoded snapshot bound has 2.4% headroom** (1.56× against 1.6×).
   This slice did **not** consume any of it: `CatalogPackage` gained no field, `CatalogSnapshot` is
   unchanged, and `CatalogFootprintTests` passed unchanged with a zero-line diff. The next widening
   of the cask projection still crosses it at any size, so slices 3–5 must re-price against it.

## Remaining Verify Findings (non-blocking, closed as recorded)

- **WARNING** — the XCUITest activation flake, the arrivals bound headroom, and task 6.5's unobserved
  RED. All three are carried above.
- **SUGGESTION** — `apply-progress` names `DiscoveryStructuralGuardTests` as a file though the suite
  lives in `DiscoverySidecarFootprintTests.swift`; the `cellarTests` count is 56 measured against 57
  reported (a parameterized-expansion counting difference — the Discover contribution matches at 10,
  and **the verify figure of 56 is the authoritative one** as the higher-ranked source); the
  5,659-line grand total including lifecycle artifacts against 4,457 authored is worth stating in a
  PR; one SwiftLint `orphaned_doc_comment` at `DiscoverSectionModels.swift:9`;
  `AppTestFixtures.catalogDirectory` puts a launch-argument branch on a production path (M3/M4
  precedent, worth a PR line); coverage is not measured (`threshold: 0`).

## Milestone Linkage

| Field | Value |
|---|---|
| PRD milestone | **M5 — "Pro-parity flows"** (PRD §7); feature §3.1 (Discover tab, as amended) |
| Slice | **2 of 5** — `m5-discover` |
| Milestone state after this archive | **OPEN** — 3 slices remain |
| Remaining slices | `m5-release-notes` (3), `m5-brewfile` (4), `m5-health` (5) |
| Pattern established for later slices | The **new-sidebar-section** pattern (`AppSection` case + `ContentView` arms + a `PBXFileSystemSynchronizedRootGroup` view directory, with no pbxproj edit) is now proven twice and is what slice 5 reuses for Health. |
| Ordering edge | None introduced. Slice 1's edge into slice 3 (`urls.stable` / `urls.head` already projected) is unaffected by this slice. |
| Shared exploration | `openspec/changes/m5-pro-parity/explore.md` — serves all five slices, **left active, not archived** |

## Engram Traceability

The following full observations were read (not previews) and used:

| Artifact | Observation |
|---|---:|
| Proposal (rev 2, D1–D5 resolved) | #7492 |
| Proposal question round / mechanism correction | #7493 |
| Specification (rev 2, sidecar-versioning ADR amended) | #7494 |
| Design | #7495 |
| Tasks (rev 3, 52/52) | #7496 |
| Apply progress | #7497 |
| Verify report (rev 2 = pass; rev 1 was the fail) | #7499 |
| M5 exploration | #7476 |
| M5 decision round (five-slice split) | #7477 |
| Slice-1 archive report | `sdd/m5-catalog-inspection/archive-report` |
| This archive report | `sdd/m5-discover/archive-report` |

`apply-progress` for this change exists **only in Engram** (#7497); as with
`2026-08-06-m5-catalog-inspection`, there is no `apply-progress.md` file in the change folder, and
there is no `state.yaml`. Recorded so a future reader does not go looking for files that were never
written.

## Mechanical Archive Evidence

Every artifact was copied and moved with `cp`/`mv`/`git mv` only; no file content passed through a
Read→Write path. Every `diff -r` readback was **empty**. The archive move was compared against a
pre-move recursive snapshot, taken before this additive report was created.

### Merged spec assembly — verified slice by slice

Both main specs were assembled by **byte-slicing**, never regenerated. Each slice was extracted back
out of the assembled candidate and diffed against its source; all eight diffs were empty.

#### `catalog-sync` — candidate slices vs sources

```text
### catalog-sync slice A (candidate vs source)
[exit 0]
### catalog-sync slice B (candidate vs source)
[exit 0]
### catalog-sync slice C (candidate vs source)
[exit 0]
### catalog-sync slice D (candidate vs source)
[exit 0]
### catalog-sync slice E (candidate vs source)
[exit 0]
### catalog-sync slice F (candidate vs source)
[exit 0]
```

Slice A = main lines 1–197; B = delta lines 48–152 (the *Slim persisted projection* MODIFIED block);
C = main lines 267–493 (every untouched requirement between the two replacements); D = delta lines
153–189 (the *Inspection data* MODIFIED block); E = delta lines 192–309 (both ADDED requirements);
F = main lines 518–624 (the provenance section). 791 lines assembled, 791 expected. Requirement
headings are unique — no duplicate name survived the merge.

#### `package-discovery` — candidate slices vs sources

```text
### package-discovery slice B — description (candidate vs delta)
[exit 0]
### package-discovery slice D — every requirement body (candidate vs delta)
[exit 0]
```

Slice B = delta lines 6–12 (the capability description); D = delta lines 21–251 (all six requirements
and all 23 scenarios, byte-identical). 242 lines assembled, 242 expected. The only authored bytes in
the promoted body are four lines: the `# package-discovery` header, its blank line, the
`## Requirements` wrapper and its blank line. The delta's bookkeeping preamble (its "New capability
— there is no … yet" summary and its D1–D5 traceability paragraph) was **not** promoted into the
requirements body; the traceability was carried into the provenance section instead, following the
convention `m3-services` established for `service-management`.

#### Candidate → installed main spec

```text
### openspec/specs/catalog-sync/spec.md : candidate -> installed
[exit 0]
### openspec/specs/package-discovery/spec.md : candidate -> installed
[exit 0]
```

Each was written to a `mktemp` file inside the target directory, diffed, then `mv`-ed into place. No
temporary files remain.

#### Provenance sections — additive only

`catalog-sync` gained exactly one authored provenance bullet, inserted before the closing "the
archived delta specs are the verbatim audit trail" bullet, matching the convention this file has
carried since the `m3-hardening-prelude` amendment. `package-discovery`, as a newly established
capability, gained a whole `## Provenance` section appended after its last scenario, matching the
`service-management` and `tap-management` convention. Both verified additive:

```text
### catalog-sync head 1..789 unchanged by provenance edit
[exit 0]
### catalog-sync closing audit-trail bullet unchanged
[exit 0]
### only additions (zero deletions) vs pre-provenance file
  deleted lines: 0 — ZERO deleted lines, additive only
  added lines:   49

### package-discovery head 1..242 unchanged
[exit 0]
### only additions vs pre-provenance file
  deleted lines: 0 — ZERO deleted lines, additive only
  added lines:   44
```

### Change source → pre-move snapshot → archived destination

```text
pre-move snapshot files: 6
moved via: git mv
source directory is gone: confirmed
### diff -r  pre-move snapshot  vs  archived destination
[exit 0]
```

## Archive Integrity

- Archived at `openspec/changes/archive/2026-08-06-m5-discover/`.
- Proposal, design, tasks, both delta specs and the verify report are present. `apply-progress` lives
  in Engram only (#7497); no `state.yaml` was ever written for this change.
- The active source directory `openspec/changes/m5-discover` is gone.
- Archived tasks remain **52/52 checked**; no reconciliation was needed or authorized.
- `openspec/changes/m5-pro-parity/` remains **active by design** — the exploration serves all five M5
  slices and was neither moved nor modified.
- `openspec/changes/m3-4/` and `openspec/changes/m3-services-cleanup-taps/` remain separate active
  artifacts and were neither moved nor modified.
- Nothing was committed or pushed by this phase; the archive changes are left in the working tree.
