# Archive Report: `m5-brewfile`

**Archived**: 2026-08-07 · **Milestone**: PRD **M5** "Pro-parity flows", **slice 4 of 5**
**Status at close**: shipped and merged · **Verify verdict**: PASS WITH WARNINGS
**Artifact store**: hybrid (OpenSpec + Engram, project `swiftui_cellar`)

This report is the terminal record of the cycle. It describes the state of the change **at close**,
not the state at any earlier point. Where an intermediate snapshot (`verify-report`,
`apply-progress`) disagreed with the final state, the final state is recorded here and the
snapshot's claim is attributed to its own moment.

---

## 1. Milestone linkage

- Closes **M5 slice 4 of 5** — Brewfile import & export, anchored to PRD.md **M5** (§7), feature
  **§3.7 "Taps & Brewfile"**.
- **M5 remains OPEN.** One slice remains: **`m5-health`** (slice 5).
- Slices 1–3 (`m5-catalog-inspection`, `m5-discover` archived 2026-08-06; `m5-release-notes`
  archived 2026-08-07) all closed before this one. This slice consumed **none** of slice 1's
  encoded-snapshot footprint headroom (S4): it added no catalog field, moved no schema version, and
  `CatalogFootprintTests.swift` is untouched and passes un-rebased.

## 2. Delivery references

| Item | Value |
|---|---|
| Pull request | **#19** (`feature/m5-brewfile` → `main`) |
| Merge commit | **`5cb4291`** |
| Implementation commit | `d3a83fb` — `feat(brewfile): Brewfile export and import with diff preview and selective apply` |
| Lifecycle commit | `89de7c3` — `docs(sdd): record the m5-brewfile lifecycle` |
| Working tree at archive | clean, branch `main` at `5cb4291`, synced with `origin` |

## 3. Review gate

Receipt-driven development is **disabled for this clone**. Structured status carried **no
`reviewGate` key** — the key is structurally absent, there is no `disabled/unmanaged` value to
check, and no review was ever started for this candidate. Per the archive contract, archive
proceeded under **ordinary repository policy**. No review tooling was invoked, and **nothing in this
report claims a review approval that does not exist.**

## 4. Task completion gate

**61 / 61 tasks complete; zero unchecked (`- [ ]`) entries** in the archived `tasks.md`, verified
mechanically before any spec sync or folder move. No stale-checkbox reconciliation was needed or
performed.

- The tasks artifact's own header said "63"; that was a **miscount** recorded in Engram `#7524`. The
  mechanical count is 61, and 61 is what the archived artifact carries.
- **Task 10.4 (user-facing copy review) closed 2026-08-07** by explicit user acceptance: the
  `BrewfileApplyAdvisory` sudo-cask message, the six skip-reason sentences, the skip-group shape and
  the four import-summary lines were presented **verbatim** and accepted **as-is, with no
  rewording** (Engram `#7520`, and the annotation on the 10.4 checkbox itself).

## 5. Spec sync

Two capability deltas. One is ADDED-only; the other is a **destructive delta** into an existing main
spec and was handled under the explicit rule below.

| Domain | Action | Details |
|---|---|---|
| `brewfile-management` | **Created** | 9 requirements / 38 scenarios added; 0 modified, 0 removed, 0 renamed |
| `package-mutation` | **Updated** | 2 MODIFIED (PM1, PM9), +5 scenarios; 0 added, 0 removed, 0 renamed. 9 req / 43 scen → **9 req / 48 scen** |

### 5.1 `brewfile-management` — new capability, ADDED-only

- **Source**: `openspec/changes/archive/2026-08-07-m5-brewfile/specs/brewfile-management/spec.md`
- **Promoted to**: `openspec/specs/brewfile-management/spec.md` (new file; the capability had no
  main spec)
- **Promotion convention** followed from `2026-08-06-m5-discover` and `2026-08-07-m5-release-notes`:
  `# Delta for brewfile-management` → `# brewfile-management`; the ADDED-only preamble and the
  traceability paragraph moved into a `## Provenance` section; `## ADDED Requirements` →
  `## Requirements`. The capability-ownership paragraph, the "Amended after design" (DD1) paragraph
  and the "Why the security invariants are requirements and not comments" paragraph were carried
  into the header by mechanical `cp`, never re-typed.
- **Mechanical copy + readback**: `cp` into a `mktemp` sibling, `diff -r` source vs. temp →
  **empty, exit 0**, then `mv` into place. Only after that were the four header transforms applied.
- **Post-promotion integrity**: `diff` delta vs. promoted file shows **exactly 22 deleted lines**,
  and they are exclusively the delta title, the two-line "New capability … ADDED-only" preamble, the
  eleven-line Traceability paragraph, the `## ADDED Requirements` heading and their blank
  separators. **No requirement or scenario byte was deleted or altered.** Counts identical on both
  sides: **9 requirements / 38 scenarios**.

### 5.2 `package-mutation` — DESTRUCTIVE delta, merged after a structural superset proof

**Config rule `rules.archive`: "Warn before merging destructive deltas."** The rule fired. The
orchestrator warned the user that this delta replaces two whole requirement blocks in a shipped main
spec, and **the user directed archive to proceed.** The merge was then gated on structural evidence,
not on the delta's own prose claim of being a superset.

**Superset proof method** — byte-slicing the exact replaced ranges and diffing them, per the slice-3
verification standard. Prose assertions in the delta header were treated as claims to be tested, not
as evidence.

| Block | Main range replaced | Delta range | `diff` result |
|---|---|---|---|
| **PM1** "Every mutation is a typed command carrying an explicit kind flag" | lines 22–81 | lines 39–134 | 1 `c` hunk + 2 pure-addition hunks |
| **PM1** — its six original scenarios | main 43–81 | delta 74–133 | **empty diff — verbatim** |
| **PM9** "Every mutation command is validated at construction, with no bypass" | lines 461–488 | lines 136–192 | **pure additions only, zero `<` lines** |
| **PM9** — its three original scenarios | main 470–488 | delta 159–192 | **empty diff — verbatim** |

**PM9 is an unqualified strict superset**: every line of the replaced block appears verbatim, and
the diff contains only `>` additions.

**PM1 required one honest qualification, recorded rather than glossed.** Its diff carried a single
`c` hunk — five deleted lines — and they were examined word-by-word before the merge was allowed:

1. **Three lines: the projections sentence, rewrapped to add an item.** Word-level diff shows the
   only change is `and the state domains it invalidates` → `the state domains it invalidates, and
   **the confirmation disclosure it carries**`. That is an Oxford-comma shift plus an **addition to
   an enumeration**. Every original clause survives; nothing normative was removed.
2. **Two lines: the superseded rolling `(Previously:)` annotation.** The note m3-services left on
   PM1 was replaced by this slice's note about the disclosure, following the
   one-rolling-note-per-block convention already visible across the main specs. This is
   delta-convention bookkeeping, **not requirement text**, and its substance was already durably
   recorded in the `## Provenance` m3-services entry. The supersession is now recorded explicitly in
   `package-mutation`'s Provenance so a future reader cannot mistake it for a silent deletion.

**Conclusion**: PM1 is a strict superset of all **normative** text and of all six original
scenarios verbatim; the one non-additive edit is a non-normative annotation whose content is
preserved elsewhere. On that basis, and with the user's explicit direction, the merge proceeded.

**Merge mechanics and post-merge readback.** The merge was performed by `awk` range-splicing in the
shell — no artifact content passed through a Read → Write path. Five independent readbacks, all
**PASS**:

| Readback | Comparison | Result |
|---|---|---|
| Header + `## Requirements` wrapper unchanged | before 1–21 vs. after 1–21 | **empty diff** |
| PM1 block equals the delta verbatim | delta 39–134 vs. after 22–117 | **empty diff** |
| **The seven untouched requirements are byte-identical** | before 82–460 vs. after 118–496 | **empty diff** |
| PM9 block equals the delta verbatim | delta 136–192 vs. after 497–553 | **empty diff** |
| Existing `## Provenance` preserved intact | before 489–624 vs. after 555–690 | **empty diff** |

Whole-file `diff` before → after: **5 deleted lines** (exactly the two examined above) and 71 added
lines. Final counts: **9 requirements / 48 scenarios**, matching 43 − 9 + 14 exactly.

### 5.3 What was written into both main specs

Each promoted spec gained a `## Provenance` section recording D1–D6 (and DD1) **with what each
rejected**, so a later change cannot reintroduce a rejected alternative as a fresh idea — most
importantly that the PRD's literal `brew bundle --file` diff preview was **refused on evidence**,
not on preference.

## 6. The finding that justifies this slice's shape

Recorded here because it is the durable reason the capability is written the way it is.

- **Probe U8** (2026-08-07, Homebrew 6.x, Engram `#7519`) established as **fact, not inference**,
  that `brew bundle check --file <path>` **evaluates the Brewfile's Ruby**. A Brewfile whose only
  content was `File.write(".../marker.txt", …)` left the marker on disk after what PRD §3.7 calls a
  "read-only diff preview". **The PRD's literal implementation runs a stranger's code.** The product
  outcome was delivered; that implementation was refused, and the refusal is pinned by testable
  requirements rather than by a comment.
- **Design decision DD1 found a live, security-relevant defect in shipped code.**
  `OperationCenterBulk.swift:141` recovered the confirmation disclosure by concrete-type downcast
  (`(first as? TapCommand)?.disclosure ?? .packageRemoval`) while `AnyBrewMutation` carried only
  seven projections, `disclosure` among neither them nor the `BrewMutating` requirements. Every
  shipped call site happened to submit an unerased `TapCommand`, so **the gap had never fired**. A
  Brewfile mixed tap+install batch is the first erased submission, at which point the downcast fails
  and the sheet would silently show the package-removal disclosure instead of the tap-trust warning.
  Fixed as a **requirement** (PM1), not as an implementation detail. Verified in source at close:
  `rg 'as\? *TapCommand'` finds **zero** executable occurrences (4 hits = 3 doc comments + 1
  structural guard scanning for the string), and `OperationCenterBulk.swift:149` reads
  `disclosure: first.disclosure`.

## 7. Verification at close

`verify-1` settled `complete` on the first pass — **no remediation, no ledger reset, no attempt
retry**. Attempt ledger: `apply-batch-1`, `apply-batch-2`, `verify-1`, all settled `complete`.

**Verdict: PASS WITH WARNINGS** — **0 CRITICAL · 0 blockers · 6 WARNING · 4 SUGGESTION**
(Engram `#7526`; full bytes at `verify-report.md` in this folder,
`sha256:5f45db4b603d7440e24909df38d1a48775593eb5798d712fc26b68d0dd3991f1`). Admitted by
`gentle-ai sdd-verify-validate --requirements 11 --scenarios 52` → `valid: true`.

- **Spec compliance: 52 / 52 scenarios COMPLIANT**, 0 UNTESTED, 0 FAILING.
- All security invariants were verified **in source**, not by assertion: `dump` is the only
  representable `bundle` subcommand (`BundleDumpCommand.Subcommand` is a one-case `CaseIterable`
  whose only initialiser is `init(fileURL:)` — no `String` overload); no Ruby is evaluated
  (`trailingConditional` *detects* `if`/`unless` in order to refuse, never to evaluate);
  `trusted:` is parsed and surfaced but `rg` over `BrewfilePlan`/`BrewfileDiff` finds **zero**
  `trusted`/`Claim` references; names are admitted only through `TapName`/`FormulaID`/`CaskID`; and
  `MutationName.isSafe` is **unchanged**.
- **Strict TDD: 7/7 checks passed** over a 21-row cycle-evidence table, with credible RED reasons.
- **Assertion quality: 0 CRITICAL, 0 WARNING** across 867 assertions in 20 changed test files. The
  slice-3 per-instance-spy rule was **satisfied**: `BrewfileCompositionLedger` is a
  `Mutex<[String:[[String]]]>` keyed by per-launcher UUID, and `CompositionRequestSpy` was
  deliberately **not** reused.

### 7.1 Correction to `verify-report` WARNING 1 — resolved after the report was written

> **Final-State Authority.** `verify-report`'s **WARNING 1** stated that `apply-progress` was stale
> in both backends, claiming "partial — 60/61" with task 10.4 unchecked. **That was true at
> verification time and is no longer true at close.** Both backends were corrected afterwards:
> `apply-progress.md` in this folder and Engram `#7525` (revision 3) now read **61/61 COMPLETE**
> with 10.4 closed. WARNING 1 is **CLOSED** and is deliberately **not** carried into §10. No other
> verify warning changed state after the report was written.

## 8. Test and build state at close

| Layer | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,517 tests / 188 suites green**, exit 0 (baseline 1,396) |
| `xcodebuild test -only-testing:cellarTests` | **100 cases passed, 0 failed** — TEST SUCCEEDED |
| `xcodebuild test -only-testing:cellarUITests/BrewfileImportUITests` | **2 / 2 passed** |
| `xcodebuild build -scheme cellar` | **BUILD SUCCEEDED**, exit 0 |
| `Package.swift` · `project.pbxproj` | **zero-line diffs** (held as a binding) |
| `CatalogFootprintTests.swift` | untouched, passes un-rebased — **S4 headroom unconsumed** |
| SwiftLint over 40 changed files | 30 warnings, 3 errors — **all 3 errors pre-existing and byte-identical at `7d48779`**, proven in an isolated worktree. **Zero new lint errors.** |

**Pre-existing failures, NOT attributable to this change** — each proven at clean `main` `7d48779`
before this change existed, and recorded separately rather than merged into one story:

- `cellarUITests/ReleaseNotesUITests` — **exactly 4 cases / 7 failures.** This change touches zero
  release-notes files. FULL is therefore still not green on this repo.
- `OperationCenterCancelTests.swift:183` — 1 known issue in the CellarCore package suite.
- The 3 SwiftLint errors listed above.

> **A state change worth recording**: slice 3 carried "XCUITest environment breakage, machine-wide"
> as an open follow-up that left its E2E cases unexecuted. XCUITest **now executes** —
> `BrewfileImportUITests` ran 2/2 green in this slice. The remaining `ReleaseNotesUITests` failure
> is a **specific, undiagnosed, unowned test failure**, not the old machine-wide block. It is
> carried in §10 with that distinction intact; no cause is claimed, because none was confirmed.

## 9. Recorded exceptions and authorizations

- **`size:exception` — user-accepted** (Engram `#7520`). Delivered at **7,438 authored lines**
  (7,427+ / 11−, excluding 2,229 lines of OpenSpec lifecycle markdown; 7,066 excluding byte-exact
  fixtures) against a **5,000**-line session budget — roughly **49% over**. `sdd-tasks` forecast
  6,500–9,500 authored with guard lines `Decision needed before apply: Yes` / `Chained PRs
  recommended: Yes` / `400-line budget risk: High`, named this a real fork, and offered three
  options; the user chose **Option A** (single PR with `size:exception`), honouring the cached
  `delivery_strategy: single-pr`. Precedent: Engram `#7509` (slice 3).
  - The forecast was **deliberately raised above the proposal's** 2,600–4,200 by applying the
    measured 1.9–2.3× correction from slices 1 and 3 to a bottom-up count. Actual 7,438 landed
    inside the 6,500–9,500 forecast band — the first slice whose forecast was not beaten in the
    same direction.
  - Tests and fixtures are **66%** of the diff; shipped source is 2,347 lines.
  - The pre-agreed mid-apply cut points (Phase 3 first, Phase 9 second) were honoured: apply stopped
    at Phase 9 when the measured diff crossed 5,000 at the end of Phase 8, and batch 2 resumed at
    task 9.1.
- **User-facing copy accepted as-is** (Engram `#7520`, task 10.4) — all Brewfile copy presented
  verbatim and accepted with no rewording.
- **Destructive `package-mutation` merge authorized** — the `rules.archive` warning was raised to
  the user, who directed archive to proceed. The structural superset proof in §5.2 is the
  independent evidence that made proceeding safe.

## 10. Carried follow-ups (recorded open, deliberately not closed here)

**From this slice's verification** (`verify-report` warnings 2–6 and suggestions 1–4; WARNING 1 is
closed — see §7.1):

1. **`BrewfileParser.entry(kind:…)` cyclomatic complexity 15 vs. limit 10.** This is the
   **security-critical admission function** — the one that decides what becomes an entry and what
   becomes a counted skip. Complexity there is a maintenance hazard with security consequences, so
   this is the highest-value item on this list.
2. **`BrewfileCompositionTests.swift` is 808 lines against the project's 400-line convention**;
   `BrewfileStoreTests.swift` 443 and `BrewfileParser.swift` 432 also exceed it.
3. **A10 traded an exact claim for a magic number.** `TapShippingProofTests` now asserts
   `components(separatedBy: "Brewfile").count - 1 <= 12` instead of the exact `"Brewfile"`-excluded
   claim. Verify judged it **net stronger**, but it carries roughly **6 occurrences of headroom**
   before it stops constraining anything.
4. **`ENABLE_USER_SELECTED_FILES = readonly` sits inert behind `ENABLE_APP_SANDBOX = NO`**
   (`project.pbxproj:425/428` and `457/460`). If the sandbox is ever enabled, this combination
   **blocks Brewfile export writes while still permitting import reads** — a latent trap that would
   surface as a confusing half-working feature. Verify SUGGESTION 3 asks for a tracked issue rather
   than only a source comment. *Line numbers are as of `5cb4291`; re-locate before citing them.*
5. **`ReleaseNotesUITests` (4 cases / 7 failures) has no owner.** Pre-existing, proven at clean
   `7d48779`, undiagnosed. It is the reason FULL is not green on this repo. Not this change's
   defect — but it now blocks a clean full-suite signal for every future slice.
6. **BF7's inherited-coverage gap.** "A mid-batch failure attributes to one entry" is compliant only
   by *inherited* spine coverage (`BulkFanOutTests`, `OperationCenterHistoryTests`), not by a
   Brewfile-specific case. Verify SUGGESTION 1 asks for one Brewfile-level case (3 entries, the 2nd
   exiting non-zero) — worth doing precisely because DD1 changed the erased path it runs on.
7. **`BrewfileCompositionLedger`'s backing store is process-global and never pruned.** Harmless at
   current scale, and it does **not** carry the false-zero shape — but it wants a teardown hook.
8. **9 mechanical `optional_data_string_conversion` lint warnings** could be swept.

**Inherited from earlier slices, still open:**

9. **`CompositionRequestSpy` still holds the false-zero shape.**
   `cellarTests/SecurityCompositionSupport.swift:181` still uses
   `nonisolated(unsafe) private static var count = 0` with an `install()` reset. **This slice
   deliberately did not reuse it** and added no new call site to it, but the M4 file and slice 3's
   call site are unchanged. Fix: fold it into the per-instance tagged shape this slice used.
10. **Slice-1 W2 — decorative assertion**, carried forward from `m5-catalog-inspection`. Untouched
    here. *Check current line numbers before citing.*
11. **S4 — encoded-snapshot bound headroom remains ~2.4%.** This slice consumed **none** of it, but
    future catalog work still faces the same narrow margin.
12. **`RecordingURLProtocol.ledgers` grows without teardown** (slice-3 follow-up 5). Same shape as
    item 7 above; both want the same cleanup hook.

**Closed since slice 3, recorded so it is not re-raised:** `openspec/config.yaml` now reads
`review_budget_lines: 5000` **and** `rules.tasks` line 56 reads "Forecast the 5,000-line review
budget explicitly." The stale-prose follow-up from the slice-3 archive report (§6, follow-up 6) is
**resolved**.

## 11. Artifact traceability (Engram observation IDs)

Artifacts read in full for this archive (`mem_get_observation`, never search previews):

| Artifact | Topic key | Observation |
|---|---|---|
| Explore | `sdd/m5-brewfile/explore` | **`#7518`** |
| Probes (U6 / U8 / U9) | — | **`#7519`** |
| Decisions (incl. task 10.4 closure, `size:exception`) | — | **`#7520`** |
| Proposal | `sdd/m5-brewfile/proposal` | **`#7521`** (rev 1) |
| Spec | `sdd/m5-brewfile/spec` | **`#7522`** (rev 2 — amended after design/DD1) |
| Design | `sdd/m5-brewfile/design` | **`#7523`** (rev 1, amendments A1–A12 in `design.md`) |
| Tasks | `sdd/m5-brewfile/tasks` | **`#7524`** (rev 2) |
| Apply progress | `sdd/m5-brewfile/apply-progress` | **`#7525`** (rev 3 — the 61/61 FINAL revision) |
| Verify report | `sdd/m5-brewfile/verify-report` | **`#7526`** (rev 1) |
| Delivery | — | **`#7527`** |
| **This archive report** | `sdd/m5-brewfile/archive-report` | *saved at close* |

Referenced precedent: `#7509` (slice-3 `size:exception`), `#7182` (M3 services product ruling),
`#7101` (M2 upgrade-selected ruling) — all cited from the promoted `package-mutation` Provenance.

## 12. Archive integrity

All file movement was mechanical (`cp`, `cp -R`, `git mv`, `awk` range-splicing) and verified by
independent `diff` / `diff -r` readbacks. **No artifact content passed through a Read → Write path.**

| Check | Result |
|---|---|
| New main spec created correctly | ✅ `openspec/specs/brewfile-management/spec.md`, 9 req / 38 scen |
| Existing main spec merged correctly | ✅ `openspec/specs/package-mutation/spec.md`, 9 req / 48 scen |
| Delta bodies byte-identical in both promotions | ✅ empty `diff` on every slice (§5.1, §5.2) |
| Seven untouched `package-mutation` requirements preserved | ✅ empty `diff`, before 82–460 vs. after 118–496 |
| Destructive merge warned and authorized before merging | ✅ user directed proceed; superset proved structurally first |
| Change folder moved to archive | ✅ `git mv` → `openspec/changes/archive/2026-08-07-m5-brewfile/` (history-preserving; all 8 files show as `R` renames) |
| Archived tree byte-identical to pre-move snapshot | ✅ **empty `diff -r`, exit 0** |
| Archive contains all artifacts | ✅ `explore.md`, `proposal.md`, `specs/`, `design.md`, `tasks.md`, `apply-progress.md`, `verify-report.md` |
| Archived `tasks.md` has no unchecked tasks | ✅ 61 / 61 complete |
| Active changes directory no longer holds this change | ✅ removed |
| Other active changes untouched | ✅ `m5-pro-parity`, `m3-4`, `m3-services-cleanup-taps` — scoped `git status` empty |

---

**SDD cycle complete.** `m5-brewfile` is planned, implemented, verified, merged (PR #19,
`5cb4291`) and archived. **M5 slice 4 of 5 is CLOSED. M5 remains OPEN — `m5-health` (slice 5) is
the one remaining slice.**
