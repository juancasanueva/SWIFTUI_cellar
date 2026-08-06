# Archive Report: M5 Catalog Inspection

`m5-catalog-inspection` closed **slice 1 of 5** of PRD milestone **M5 "Pro-parity flows"** on
2026-08-06. The change modified two shipped capabilities (`catalog-sync`, `package-detail`), added no
new capability and no new target, passed independent verification with zero CRITICAL findings, merged
to `main` as PR #16, and moved to the dated OpenSpec archive.

**M5 is not closed by this archive.** Four slices remain active: `m5-discover`, `m5-release-notes`,
`m5-brewfile`, `m5-health`. The shared exploration `openspec/changes/m5-pro-parity/explore.md` serves
all five and stays in the active changes directory until M5 completes.

The defining result of the slice is that a **measurement changed the product**. Probe U4 priced the
obvious implementation — carry the cask `artifacts` tree as decoded JSON — at +28.3 MB resident and a
4.7× launch reload over 16,214 records, and it was rejected before any of it was written. The
narrowing that followed (decision D5, triggered) removed `zap` and `uninstall` contents from a
projection the proposal had already promised to carry, and did so *against the literal text of two
earlier approved decisions*, under the authority of a third that existed for exactly that purpose.
That is recorded below as the slice's carried lesson.

## Closure Status

| Check | Final state |
|---|---|
| Requirements | 5/5 COMPLIANT (3 `catalog-sync`, 2 `package-detail`) |
| Scenarios | 31/31 COMPLIANT — zero UNTESTED, FAILING or PARTIAL |
| Tasks | 45/45 checked in the archived `tasks.md`; zero unchecked; no reconciliation needed or authorized |
| Verification | **PASS** — 0 CRITICAL, 2 WARNING, 6 SUGGESTION |
| Work units | `apply-batch-1-phases-0-8` → `passed`; `verify-1` → `complete` |
| Delivery | Merged to `main` as **PR #16** at `98c2ad9` (2026-08-06); branch `feature/m5-catalog-inspection` |
| Delivery policy | Receipt-driven development **off, clone-local**; ordinary repository policy |
| Review authority | **No receipt exists for this candidate** — see *Delivery Record* |
| Size policy | `single-pr`, no `size:exception`; measured inside the 5,000-line session budget |

`reviewGate` is structurally absent because the review kill switch is off for this clone. There is no
`disabled/unmanaged` value to check and no receipt was required, so archive proceeds under ordinary
repository policy. Nothing was silently approved: the green gates and the verify report below are the
evidence standing in place of a receipt. No review tooling was invoked at any phase of this change.

## Scope Shipped

**MODIFIED `catalog-sync`** — 2 requirements replaced as whole blocks, 1 requirement added.

- *Tolerant decoding of the published payload shapes* (5 → 10 scenarios) gains five widened cask keys
  (`url`, `sha256`, `artifacts`, `depends_on`, `conflicts_with`) and two widened formula keys
  (`urls.stable`, `urls.head`), each optional in exactly the existing sense — omitted or `null`
  decodes to typed absence, never an empty substitute, never a decode failure. An artifact stanza the
  projection cannot represent is **counted**, never dropped and never fatal.
- *Slim persisted projection with a state sidecar* (2 → 6 scenarios) gains the `schemaVersion` 1 → 2
  transition rule applied independently to **both** persisted files in **both** directions, a
  prohibition on classification throwing, failing or mutating the rejected file, and a recorded
  full-catalog footprint bound that must be asserted by a test rather than stated as a comment.
- **ADDED** *Inspection data costs no new acquisition* (2 scenarios) — the promise that outranks
  stanza coverage: no new brew invocation, no new remote resource, no per-package request, no raw
  payload retained past the sync.

**MODIFIED `package-detail`** — 1 requirement replaced as a whole block, 1 requirement added.

- *Required detail projection* (4 → 10 scenarios) gains the cask inspection fields, the projected
  stanza set with its counted remainder, the nothing-runnable rule, and the cross-record uniformity
  rule.
- **ADDED** *No pre-install signature or notarization verdict* (3 scenarios) — the explicit non-goal
  stated as a prohibition so it is testable rather than a note.

**New capabilities:** none. **New targets, products or dependency edges:** none — `Package.swift` is
untouched, and `project.pbxproj` was never edited because the `PBXFileSystemSynchronizedRootGroup`
picked both new app files up.

**Not shipped, deliberately**: any pre-install signature or notarization surface; rendering the
formula source URLs (carried for slice 3, rendered by nothing here); release-notes fetching (slice 3);
Discover (slice 2); Brewfile (slice 4); the health dashboard and bulk pin/snooze (slice 5); `zap` and
`uninstall` stanza contents (D5, below).

## Specs Synced

| Domain | Action | Result |
|---|---|---|
| `catalog-sync` | **Updated** | 2 requirements replaced as whole blocks, 1 appended. 13 requirements / 40 scenarios → **14 requirements / 51 scenarios**. The other eleven requirements are byte-identical and every pre-existing scenario inside the two replaced requirements survives byte-for-byte. |
| `package-detail` | **Updated** | 1 requirement replaced as a whole block, 1 appended. 6 requirements / 17 scenarios → **7 requirements / 26 scenarios**. The other five requirements are byte-identical and all four pre-existing scenarios survive unchanged. |

### Destructive-delta check (required by `openspec/config.yaml` `rules.archive`)

**Nothing was removed and nothing was renamed** — neither delta carries a `## REMOVED Requirements`
or `## RENAMED Requirements` section. Each MODIFIED block was diffed against the text it replaced:

- *Tolerant decoding of the published payload shapes* — **zero deleted lines**, a strict superset.
- *Required detail projection* — **zero deleted lines**, a strict superset.
- *Slim persisted projection with a state sidecar* — the **only** non-verbatim replacement in this
  merge: three lines changed. It **broadens** rather than removes. The sentence

  > A sidecar whose `schemaVersion` does not match the one the running build expects MUST be treated
  > as no cache — the system MUST re-sync from scratch and MUST NOT fail or crash on it.

  became

  > A **persisted file** whose `schemaVersion` does not match the one the running build expects MUST
  > be treated as no cache — the system MUST re-sync from scratch and MUST NOT fail or crash on it.

  so the guarantee binds the snapshot as well as the sidecar. No guarantee was weakened or dropped,
  and both pre-existing scenarios survive byte-for-byte.

**No destructive merge occurred, so no confirmation was required.** The check was run and is recorded
here rather than assumed.

### Scenario-count reconciliation (measured vs projected)

The spec observation (#7480) projected post-merge totals of `catalog-sync` 14/**49** and
`package-detail` 7/**23**. The merge was measured directly from the installed files and yields
14/**51** and 7/**26**. Requirement counts match; the projected *scenario* totals were arithmetically
low, and the measured figures are the correct ones:

- `catalog-sync`: 40 − 7 replaced + 16 in the MODIFIED blocks + 2 ADDED = **51**.
- `package-detail`: 17 − 4 replaced + 10 in the MODIFIED block + 3 ADDED = **26**.

The delta artifacts themselves are internally consistent — 16 + 2 + 10 + 3 = **31** scenarios across
**5** requirements, exactly the counts `gentle-ai sdd-verify-validate --requirements 5 --scenarios 31`
admitted. Only the observation's forward projection of the merged totals was wrong, and it is
corrected here rather than carried.

## The D5 Narrowing — the decision that defines the slice

Probe **U4** measured the per-key encoded byte delta over 16,214 records: `target` 0.84 MB,
**`zap` 1.23 MB**, `font` 0.54 MB, `uninstall` 0.19 MB, and `app` + `pkg` + `binary` together
**0.15 MB**. `zap` alone is **+34% over the entire accepted widening**.

**Decision, user-resolved and binding: `zap` and `uninstall` contents are not projected at all.** The
projected stanza set is exactly `app`, `binary` and `pkg`; every other kind — including one that did
not exist when the build shipped — is counted in the remainder and its contents are never carried.

The reasoning on the record, because the reasoning is the value:

- `zap` is not a name list. It is a directive map (`trash`, `rmdir`, `delete`, `launchctl`,
  `pkgutil`, `signal`, `login_item`, `script`), so representing it faithfully re-introduces the
  heterogeneous tree U4 rejected. **Bytes were the smaller half of the objection.**
- The binding success criterion is "download URL, checksum, **what gets installed where**,
  dependencies, auto-updates". `app`/`binary`/`pkg` answer it for 0.15 MB. `zap` answers a different
  question — what an *uninstall* would remove — which Cellar can answer at uninstall time, where
  `MutationCommand.uninstall(…, zap:)` already lives.
- **D2's five-kind list and D4's "zap and uninstall render faithfully" are superseded by D5 *as
  triggered***, which is the mechanism D5 exists to provide. This is a narrowing of a narrowing: D5's
  own written fallback was to drop `artifacts` entirely. The D5 floor is met — `url`, `sha256`,
  `depends_on` and `conflicts_with` are all retained.

A second-order benefit fell out of it. Because no directive content is projected, the old
"displayed, never executed" rule could be replaced by something strictly stronger: the projection
carries nothing that *could* be executed — no command, no script, no `launchctl`/`pkgutil` directive,
no path a removal would delete. The prohibition is now enforced by the projection's **shape** rather
than by a consumer's discipline.

## Final Gates (measured at the merged candidate)

Every number below was re-measured by `sdd-verify`, not copied forward from apply.

| Gate | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1140 tests / 156 suites passed**, 1 pre-existing known issue, 0 failures, exit 0 |
| `xcodebuild test -scheme cellar` | `** TEST SUCCEEDED **`, **65 passed cases**, exit 0 |
| `xcodebuild build -scheme cellar` | `** BUILD SUCCEEDED **`, **zero** warnings or errors, exit 0 |
| Tasks | **45 checked / 0 unchecked**, counted from the archived file |
| Validator | `gentle-ai sdd-verify-validate --requirements 5 --scenarios 31` → `valid: true, verdict: pass`; evidence revision sha256 `79ec9df8…` |

Baseline 1090 tests / 152 suites → **+50 tests, +4 suites**. The single known issue is
`OperationCenterCancelTests.swift:183`, a deliberate `withKnownIssue` in an untouched suite —
**pre-existing and unchanged by this slice**.

**No assertion was deleted or weakened.** `git diff -U0` over `Tests/` removes exactly one line,
`#expect(object["schemaVersion"] as? Int == 1)`, which task 5.4 required; it is replaced by two
stronger assertions (`== 2` and `== CatalogSnapshot.currentSchemaVersion`).

**App-suite case count, reconciled**: apply recorded FULL = 67 cases and `cellarTests` = 47; verify
independently measured **65**. Per `verify-report` (#7487) this is a counting-method difference, not a
regression — both runs report `** TEST SUCCEEDED **` with zero failures. The verify figure is the one
recorded above, as the higher-ranked source.

### Measured footprint — the bound that is now a test

| Quantity | Bound | Measured | U4's rejected raw variant |
|---|---|---|---|
| Encoded snapshot | ≤1.6× baseline, ≤16 MB | **1.56×**, 11.4 MB | 1.78× |
| Resident, loaded (malloc-zone `size_in_use`) | ≤1.6× baseline | **1.23×** | 2.59× |
| Snapshot load time | ≤2.0× baseline | **1.57×** | 4.75× |

The bound is expressed as **ratios against a same-process baseline** plus one absolute disk ceiling,
because absolute wall-clock and resident figures are machine-dependent and ratios are not. Every ratio
rejects the raw variant with headroom and accepts the trimmed one.

The anchor had to be strengthened during apply: comparing synthetic totals against a single real
record is apples-to-oranges (`cask-iterm2.json` has an unusually thin 312 B base against a 479 B slice
average). The harness now anchors **two** things independently — synthetic baseline size against 50
verbatim slice records, and the synthetic widening *delta* against the delta the same verbatim record
pays when re-projected with the widened keys stripped. Real deltas 393 B/cask and 154 B/formula;
generator 386 B and 147 B. Per the plan, **the generator was fixed, never the bound**.

## Delivery Record

- **Merged to `main` as PR #16** at `98c2ad9` — from `feature/m5-catalog-inspection`, carrying
  `080b900` *docs(prd): trim m5 scope and derive discover newness locally*, `8be0bff` *feat(catalog):
  pre-install cask inspection with widened typed projection*, and `789f0e6` *docs(sdd): record the m5
  exploration and m5-catalog-inspection lifecycle*.
- **Single PR, no size exception.** Forecast 1,500–2,100 authored lines against a 5,000-line session
  budget; measured **≈3,619 authored code + tests** (14 tracked files +967/−37, 17 new files 2,635
  lines), or **4,974 including the OpenSpec artifacts** — inside budget with 26 lines of headroom. The
  overage against the forecast is test density: the footprint harness (360), the inspection type suite
  (347) and the app suite (321) each came in larger than costed. The pre-agreed Phase 7 cut point was
  not needed.
- **Receipt-driven development: no receipt exists for this candidate.** The kill switch is off
  clone-locally, so zero review code ran and no review tooling was invoked at any phase. Delivery
  proceeded under ordinary repository policy. Recorded as fact, not as approval.
- **Rollback remains a single `git revert`.** `Package.swift` is untouched, no target membership,
  build setting or scheme was edited, and the `schemaVersion` bump is symmetric — a reverted build
  classifies a v2 file as no cache, re-syncs once and rewrites nothing.

## Two Apply-Time Amendments, Adjudicated

Both were recorded in `design.md` rather than silently absorbed, and both were independently checked
by verify.

1. **`target` is a recognised companion key, not a counted stanza kind.** The design described only
   the in-array form; `cask-iterm2.json` publishes the sibling form
   (`{"app":["iTerm.app"],"target":"…"}`). Verify confirmed the **code is correct**: counting `target`
   would make iterm2's remainder `2` where `package-detail` R5 binds it to `1`, and the sibling form
   is correct Homebrew semantics. Both serialisations attach; neither counts.
   - The two delta files' **non-normative preambles** originally listed `target` among the counted
     kinds. That was verify **SUGGESTION S1**, and it was **applied before the merge commit** — the
     archived delta specs now state that `target` is a companion key and is neither projected nor
     counted. Normative requirement text was always kind-agnostic, so there was never a normative
     conflict, and the merged capability specs are correct.
2. **The five widened keys decode with `try?`, not `try`.** Verify found this **consistent with the
   spec and compelled by it**: T5 forbids the widening from changing which records decode, so a strict
   `try` would let a cask publishing `artifacts` as an object cost a record that decoded on the
   previous build. Only pre-existing keys may cost a record. Pinned by
   `DecodeTests.anUnreadableWidenedValueCostsNoRecord`, which puts all five keys in unreadable shapes
   at once.

## Carried Follow-Ups

**Neither is a defect in what shipped.** Both are recorded so they do not disappear with the slice.

1. **W2 — a decorative assertion, deliberately not fixed.** In
   `AcquisitionScopeTests.inspectionResolvesOfflineAndWithoutBrew`, `offlineSource` is built and
   scripted but never handed to anything, so `#expect(offlineSource.requests.isEmpty)` asserts that an
   unused fake recorded nothing. **The requirement it covers is still satisfied** — A1 resolves detail
   from `loadSnapshot()` with every field asserted by value, and the no-brew half is proved
   structurally. This was a conscious decision to leave the line in place rather than an oversight.
   The fix, when taken: delete the line, or wire the fake into a real sync attempt so it can fail.
2. **S4 — the encoded footprint bound has 2.4% headroom** (1.56× measured against a 1.6× cap). The
   ratio is a **byte count**, so it is deterministic across machines and not flaky — but **the next
   widening of the cask projection crosses it at any size**. The remaining M5 slices should treat the
   `catalog-sync` footprint bound as a gate they must re-price against, not as a background
   invariant. The load-time ratio (1.57× against 2.0×) carries the widest margin and is the only
   wall-clock quantity.

Also registered, from the design's open questions and not closed here:

- **`CatalogPackage.homepage` is still a Foundation `URL`.** U4 showed `URL` costs ~2.2× `String` at
  16k scale, so the *existing* baseline carries avoidable resident bytes. Out of scope for this slice
  (not a widened key; would change a shipped field's type).
- **Artifact-stanza vocabulary drift.** The counted remainder is honest but silent about *which* kinds
  it counted. If the counts turn out to be routinely large, a debug-only kind histogram would show
  whether a fourth projected kind earns its bytes.

## Remaining Verify Findings (non-blocking, closed as recorded)

- **WARNING W1** — no canonical "TDD Cycle Evidence" table in `apply-progress`. Verify downgraded the
  strict-TDD module's default CRITICAL to WARNING **with its reasoning stated**: `tasks.md` labels
  every task RED/GREEN in order, all 45 are checked, all 20 RED tasks' test files exist and their
  suites passed under re-execution, +50 tests over a re-measured baseline, and exactly one assertion
  line was removed and replaced by two stronger ones. A format gap, not an evidence gap.
- **SUGGESTION S1** — applied before the merge commit (see *Apply-Time Amendments*).
- **SUGGESTION S2** — `tasks.md` 6.1 carries the pre-measurement footprint estimates (1.42/1.35/1.21)
  against the measured 1.56/1.23/1.57 recorded in `design.md` and in this report. The archived
  `tasks.md` is left as written; **the measured figures in this report and in `design.md` are the
  authoritative ones.**
- **SUGGESTION S3** — an unreadable whole-`artifacts` value yields absence with no count. Required by
  T5 and deliberately pinned, but a small departure from "counted and named".
- **SUGGESTION S5** — two structural scan loops lack an `#expect(names.isEmpty == false)` anchor;
  other anchors cover them.
- **SUGGESTION S6** — R10's string walk only sees `String`-backed values. **Verify reported the
  residual escape rather than hiding it**: removal paths carried in a non-`String`-backed type
  (`[URL]`, a `Data` wrapper) would evade `ExposedFields.strings` and the 4.4 vocabulary check —
  though not the 1.6× encoded footprint bound, which `zap` contents would breach on their own.
- **Non-blocking note** — R6's "remainder is `0`, not absent" is proved by composition (wire-level
  `StanzaWireTests` plus an `InspectionTypeTests` `Codable` round trip) rather than by one end-to-end
  resolved detail over a cask publishing exactly `app` + `binary` + `pkg`.

## Milestone Linkage

| Field | Value |
|---|---|
| PRD milestone | **M5 — "Pro-parity flows"** (PRD §7); features §3.1 pre-install cask inspection, §3.2 release-notes inputs |
| Slice | **1 of 5** — `m5-catalog-inspection` |
| Milestone state after this archive | **OPEN** — 4 slices remain |
| Remaining slices | `m5-discover` (2), `m5-release-notes` (3), `m5-brewfile` (4), `m5-health` (5) |
| Ordering edge unblocked | **Slice 3.** `urls.stable` / `urls.head` are projected and asserted here although nothing renders them, so release-notes resolution starts unblocked. This is the only ordering edge in M5. |
| Shared exploration | `openspec/changes/m5-pro-parity/explore.md` — serves all five slices, **left active, not archived** |

## Engram Traceability

The following full observations were read (not previews) and used:

| Artifact | Observation |
|---|---:|
| Proposal (rev 2, D1–D5 resolved) | #7478 |
| Specification (rev 2, D5-amended) | #7480 |
| Probe U4 | #7482 (cited by #7480, #7483, #7485) |
| Design | #7483 |
| Open-Question-1 resolution (zap/uninstall dropped) | #7484 (cited by #7485) |
| Tasks | #7485 |
| Apply progress | #7486 |
| Verify report | #7487 |
| M5 exploration | #7476 |
| M5 decision round (five-slice split) | #7477 |
| This archive report | `sdd/m5-catalog-inspection/archive-report` |

`apply-progress` for this change exists **only in Engram** (#7486); unlike `2026-08-06-m4-security`,
there is no `apply-progress.md` file in the change folder, and there is no `state.yaml`. Recorded so a
future reader does not go looking for files that were never written.

## Mechanical Archive Evidence

Every artifact was copied and moved with `cp`/`mv`/`git mv` only; no file content passed through a
Read→Write path. Every `diff -r` readback was **empty**. The archive move was compared against a
pre-move recursive snapshot, taken before this additive report was created.

### Merged spec assembly — verified slice by slice

Both main specs were assembled by **byte-slicing**, never regenerated. Each slice was extracted back
out of the assembled candidate and diffed against its source; all ten diffs were empty.

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
```

Slice A = main lines 1–105; B = delta lines 39–199 (both MODIFIED blocks); C = main lines 165–391
(every untouched requirement); D = delta lines 202–225 (the ADDED requirement); E = main lines
392–460 (the provenance section). 587 lines assembled, 587 expected.

#### `package-detail` — candidate slices vs sources

```text
### package-detail slice A (candidate vs source)
[exit 0]
### package-detail slice B (candidate vs source)
[exit 0]
### package-detail slice C (candidate vs source)
[exit 0]
### package-detail slice D (candidate vs source)
[exit 0]
### package-detail slice E (candidate vs source)
[exit 0]
```

Slice A = main lines 1–8; B = delta lines 32–154 (the MODIFIED block); C = main lines 43–161; D =
delta lines 157–196 (the ADDED requirement); E = main lines 162–173. 303 lines assembled, 303
expected.

#### Candidate → installed main spec

```text
### openspec/specs/catalog-sync/spec.md : candidate -> installed
[exit 0]
### openspec/specs/package-detail/spec.md : candidate -> installed
[exit 0]
```

Each was written to a `mktemp` file inside the target directory, diffed, then `mv`-ed into place. No
temporary files remain.

#### Provenance bullets — additive only

Each main spec gained exactly one authored provenance bullet, inserted before the closing
"the archived delta specs are the verbatim audit trail" bullet, matching the convention the
`m3-hardening-prelude` amendment established in `catalog-sync`. Verified additive:

```text
### catalog-sync head 1..585 unchanged by provenance edit
[exit 0]
### catalog-sync closing audit-trail bullet unchanged
[exit 0]
### only additions (zero deletions) vs pre-provenance file
  ZERO deleted lines — additive only

### package-detail head 1..301 unchanged
[exit 0]
### closing audit-trail bullet unchanged
[exit 0]
### only additions vs pre-provenance file
  ZERO deleted lines — additive only
```

The only authored bytes in either main spec are those two provenance bullets.

### Change source → pre-move snapshot → archived destination

```text
moved via: git mv
source directory is gone: confirmed
### diff -r  pre-move snapshot  vs  archived destination
[exit 0]
```

## Archive Integrity

- Archived at `openspec/changes/archive/2026-08-06-m5-catalog-inspection/`.
- Proposal, design, tasks, both delta specs and the verify report are present. `apply-progress` lives
  in Engram only (#7486); no `state.yaml` was ever written for this change.
- The active source directory `openspec/changes/m5-catalog-inspection` is gone.
- Archived tasks remain **45/45 checked**; no reconciliation was needed or authorized.
- `openspec/changes/m5-pro-parity/` remains **active by design** — the exploration serves all five M5
  slices and was neither moved nor modified.
- `openspec/changes/m3-4/` and `openspec/changes/m3-services-cleanup-taps/` remain separate active
  artifacts and were neither moved nor modified.
- Nothing was committed or pushed by this phase; the archive changes are left in the working tree.
