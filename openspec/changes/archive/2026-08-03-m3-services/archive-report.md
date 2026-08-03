# Archive Report — `m3-services` (M3-1, Service Management)

**Archived**: 2026-08-03 · **Milestone**: M3, slice 1 of 5 · **Branch**: `feature/m3-services`, draft PR **#9**
**Base**: `main` @ `3f2c166` · **Artifact store**: hybrid · **Mode**: Strict TDD
**Receipt-driven development**: **`reviewGate.delivery: disabled/unmanaged`** — the user ran
`gentle-ai review mode disable`. No `gentle-ai review *` lifecycle command was run at any phase of
this slice, and **no receipt, approval or `allow` result is claimed or implied**. Archive proceeds
under the kill-switch relaxation, which removes only the implicit demand for a terminal receipt.

---

## 1. Final state at close

This section is the terminal record. Where it disagrees with `verify-report.md` or
`apply-progress.md`, **this section is current** — those two are intermediate snapshots that were
written before the work below landed.

| Fact | Value at close | Source |
|---|---|---|
| Tasks | **94 / 94 complete** | `tasks.md`; 16.1 checked in commit `cba2b18` |
| Requirements implemented | **22 / 22** | verify pass 2 |
| Delta scenarios compliant | **90 / 93** (1 PARTIAL, 2 UNTESTED — all three SM12, all MEDIUM 1) | verify pass 2, recounted from the six delta files |
| CRITICAL findings | **0** | verify pass 2 |
| HIGH findings | **0** | verify pass 2 |
| Tests | **693 tests / 96 suites**, exit 0, 1 pre-existing known issue (`OperationCenterCancelTests.swift:183`, a deliberate `withKnownIssue` guard) | verify pass 2, reproduced independently |
| Build | `xcodebuild build` → **BUILD SUCCEEDED**, exit 0, zero warnings | verify pass 2 |
| Lint | `swiftlint --quiet` = **60** = the 0.1 baseline, **zero new** | verify pass 2 |
| Candidate size | `git diff main...HEAD --shortstat` ≈ **67 files, +8,278 / −206**, plus the later evidence commits | verify pass 2, reproduced exactly |
| Manual verification | **CLOSED on the archive-blocking subset**; remainder deferred by explicit user decision and registered as owed | task 16.1, run 2026-08-03 |

### 1.1 The archive gate, and why it is satisfied

`verify-report.md` (pass 2) returned **`verdict: fail`**. That verdict must be read precisely: it
recorded **0 CRITICAL and 0 HIGH**, upheld all five remediation claims, and failed on exactly one
gate — *"MV-7 and MV-1 have still never been run"*. Its own closing sentence states the discharge
condition: *"Run those two checks, record what you saw, and this slice is ready to archive. Nothing
else is outstanding that a human decision cannot close."*

**Both checks were subsequently run by the user in the built app on 2026-08-03 and both PASS**,
recorded in `tasks.md` 16.1 (commit `cba2b18`). The blocker is therefore discharged by a
higher-ranked source than the snapshot that raised it — the persisted tasks artifact plus the
explicit final-state account — and no contradiction remains to record. This is **not** an override of
a CRITICAL: there was no CRITICAL to override.

**MV-1 — PASS.** Services present and selected in the sidebar; `atuin` listed at **"Not running"**,
matching `brew services list`'s `none`. **No error state and no empty-state placeholder** — the
precise sentence HIGH 1 had made false. Detail pane rendered the name, the status and the plist path
`/opt/homebrew/opt/atuin/homebrew.mxcl.atuin.plist`.

**MV-7 — PASS, in full.** This is the check that **predicted CRITICAL 1 verbatim** and had never been
run. History listed **four** service entries, one per click, nothing collapsed or deduplicated,
newest-first (the exact reverse of click order, satisfying IH5):

| Title | Verb badge | Command | Outcome |
|---|---|---|---|
| **No package** | `serviceStop` | `services stop atuin` | No change |
| **No package** | `serviceStop` | `services stop atuin` | Done |
| **No package** | `serviceStart` | `services start atuin` | No change |
| **No package** | `serviceStart` | `services start atuin` | Done |

Every service row titled **"No package"** — **not** "All packages". `HistoryRecord.subject` resolves
`.noPackage` and the view renders it, so **CRITICAL 1's remediation is proven in the window, not
merely in the package tests**. No regression on package rows: the pre-existing entry still reads
`hello` / `install` / `install --formula hello`, so `.package(name)` is unaffected. Search `atuin` →
only the four service rows; search `stop` → exactly the two `serviceStop` rows. This is also the
end-to-end vindication of shipping the verbs **namespaced** rather than bare.

**MV-4 — PASS.** All four Activity summary labels captured verbatim, four rows, one per click, none
collapsed: `Done.` / `No change: it was already in that state. Homebrew reported this rather than
doing anything.` / `Done.` / the same no-change line. All four brew invocations exit **0**, and the
two no-ops are still told apart from the two real state changes. **This is the end-to-end proof that
exit 0 does not mean a state change**, and that `.noChange` renders as neither success nor failure.

**MV-3, control half — PASS.** Exactly five controls: Start at login · Run once · Stop · Restart ·
Copy command. No hidden default chooses between start and run.

**MV-5, dedupe half — PASS.** `log_path == error_log_path` on this machine
(`/opt/homebrew/var/log/atuin.log`), and the pane shows exactly one log location plus Open in
Console. The dedupe rule was load-bearing on day one.

**Machine restored to baseline and confirmed**: `brew services list` → `atuin none`; no
`~/Library/LaunchAgents/homebrew.mxcl.atuin.plist`.

**Deferred by explicit user decision — registered as owed, NOT claimed**: MV-2 (a)(b)(d), MV-5 GUI
half, MV-6, MV-8, MV-9 (needs an uncommittable fixture patch), MV-10, MV-11 GUI half, MV-12. Each
corroborates a claim that already has headless proof; none is the sole evidence for a fixed defect.

### 1.2 Brew version note

The design's probes were taken on brew **6.0.14**. Apply re-confirmed every classification marker
live on **6.0.15-4-gd610afe**: cold start exits 0 with `==> Successfully started …`; start-again exits
**0** with `Service \`atuin\` already started, use \`brew services restart atuin\` to restart.` and no
`Successfully` line; stop exits 0 with `==> Successfully stopped …`; stop-again exits **0** with
stderr `Warning: Service \`atuin\` is not started.` The markers are stable across the version bump.

Apply also obtained the **start-vs-run discriminator** live, and it found something: `brew services
run` does **not** write the LaunchAgents plist, `brew services start` from a **stopped** service does,
and `start` on an *already running* service takes the already-started branch and does **not** register
it. MV-3 must therefore be run from a stopped service or it reports a false negative.

---

## 2. Specs promoted

Promotion replaces a MODIFIED requirement **by name** and preserves every requirement not named in a
delta. Six delta files were promoted.

| Capability | Action | Delta | Requirements | Scenarios |
|---|---|---|---:|---:|
| `service-management` | **CREATED** | 12 ADDED | 0 → **12** | 0 → **40** |
| `package-mutation` | Updated | 4 MODIFIED (PM1, PM4, **PM6 renamed**, PM7) | 9 → 9 | 34 → **40** |
| `installation-history` | Updated | 3 MODIFIED (IH1, IH5, IH7) | 7 → 7 | 23 → **28** |
| `installed-inventory` | Updated | 1 MODIFIED (II10) | 14 → 14 | 55 → **57** |
| `operation-activity` | Updated | 1 MODIFIED (OA6) | 6 → 6 | 23 → **24** |
| `brew-execution` | Updated | 1 MODIFIED (BE1) | 6 → 6 | 20 → **22** |

**Destructive-delta count: ZERO.** Every MODIFIED block is a strict superset of the text it replaced.
Nothing was REMOVED, no shipped scenario was deleted, and no MUST was weakened. The one rename is
PM6, handled below.

### 2.1 Post-promotion shipped-spec totals — computed from the files, not carried from the plan

| | Before | After |
|---|---:|---:|
| Capabilities | 10 | **11** |
| Requirements | 80 | **92** |
| Scenarios | 269 | **325** |

Scenario arithmetic: +40 (`service-management`) +6 (`package-mutation`) +5 (`installation-history`)
+2 (`installed-inventory`) +1 (`operation-activity`) +2 (`brew-execution`) = **+56**.

**This corrects the planning artifact's figure of 322, in two independent ways, and both are recorded
rather than quietly adopted:**

1. The `sdd-spec` mirror's own per-capability table summed to **+55** while its total line said
   **+53** — an arithmetic slip of 2 in the artifact itself.
2. It was written **before** task 18.8, which added one further `installation-history` scenario (the
   IH1 presentation scenario), moving that capability from +4 to **+5** and the delta total from 92 to
   **93** scenarios. `sdd-verify` pass 2 independently recounted the six delta files and confirmed
   **22 requirements / 93 scenarios**, which is the figure this promotion matches.

The delta files' own summary headers still carry the pre-18.8 counts (`installation-history`'s says
"14 scenarios … 23 → 27"). They are archived unedited as the historical record; the authoritative
counts are the recounted ones above.

### 2.2 PM6 — renamed in place, verified after promotion

The requirement's **title changed**, not merely its body:

- **Old**: *"Every terminal outcome forces one re-snapshot, and cancel is reported honestly"*
- **New**: *"Every terminal outcome forces one refresh of each state domain the command invalidates,
  and cancel is reported honestly"*

Because promotion replaces by **name**, a naive promotion would have **added** the new requirement
while **leaving the old one in place**, and `openspec/specs/package-mutation/spec.md` would then carry
two contradictory versions of PM6 — one saying the re-snapshot is unconditional, one saying it is
scoped.

**It was executed as a single rename-in-place edit**: the old-titled block, its body and its three
scenarios were removed in the **same** edit that inserted the new title, the new body and its five
scenarios. **Verified after promotion**: no `### Requirement:` heading in
`openspec/specs/package-mutation/spec.md` carries the old title, the capability holds exactly **9**
requirements (not 10), and no duplicate PM6 exists. The old wording survives in exactly one place —
inside the `## Provenance` entry below, which quotes it deliberately to record what the rename
changed. This was flagged as an archive hazard by `sdd-spec` (flag 5),
carried into `tasks.md` 15.1, restated in the delta header as an explicit instruction to the archive
step, and re-flagged by the orchestrator at launch. It was the highest-risk mechanical step in this
archive and it is closed.

### 2.3 The `package-mutation` header prose was already reconciled — deliberately not touched again

`openspec/specs/package-mutation/spec.md`'s capability header (lines 1–14) described the
**unconditional** re-snapshot at every terminal outcome. Header prose sits **outside** delta scope and
would have survived promotion untouched, contradicting the amended PM6. It was corrected **during
apply** (task 15.2), on this branch, header only — no requirement text, no scenario. This archive
verified it was already correct and **did not reconcile it a second time**. It is not an unexpected
shipped-spec edit.

`installation-history`'s header was **checked and needed no edit** (also task 15.2): it names no
forced inventory re-snapshot in the singular. Recorded rather than silently skipped.

### 2.4 Reconciliation carried out at this archive

One item, from verify pass 2's SUGGESTION 2: **IH1's `(Previously: …)` note was incomplete.** The
requirement body now constrains **presentation**, but the note still listed only the verb vocabulary,
the null-package shape and collapsing — so the promoted requirement's own history would have been
inaccurate about the very gap that produced CRITICAL 1. The note was extended at promotion to state
that the requirement previously constrained **storage only** and said nothing about how a
null-package entry must be **presented**, which is how a service entry came to be displayed as "All
packages". Requirement text and scenarios are otherwise byte-identical to the delta.

### 2.5 What was deliberately NOT promoted

- **`brew-execution` BE3 ("Terminal result and exit handling") was not re-modified.** M2-3 follow-up
  **S1** was already closed by `m3-hardening-prelude` (M3-0). The umbrella explore's §3 row listing it
  as M3 work is stale. Re-modifying it would have been a no-op block carrying regression risk.
- **`installed-inventory` II13 is untouched, and that is load-bearing.** Its "Only upgrade and
  uninstall are offered for a selection" is proven exhaustively over `BulkSelection.Action.allCases`.
  This slice ships **no** bulk service affordance; SM4 carries a guard scenario asserting the same
  fact from the services side so the two cannot drift.
- **`package-mutation` PM2, PM3, PM5, PM8, PM9** and **`installation-history` IH2, IH3, IH4, IH6** are
  byte-identical. **IH3 gets no carve-out** (product ruling a) — rejected alternatives recorded so the
  decision is not silently reopened: an IH3 carve-out excluding service verbs, recording start/stop
  only, and a separate services activity store.
- **`package-detail`, `package-search`, `brew-detection`, `local-package-metadata`, `catalog-sync`**
  were not in the delta and are untouched. SM12 re-asserts the no-service-predicate rule from the
  services side so a future change cannot quietly push service state into the search index.

---

## 3. What shipped

`BrewMutating` generalises the mutation spine so a **second family** enters it without any package
rule loosening — and, unlike the M2-1 `InstalledMutationGate` anti-precedent, the seam ships **with a
real second consumer in the same slice**. `MutationCommand` conforms in a three-line extension, so
PM1's "exactly six" stays **literally** true; `submit` is generic rather than existential, so every
app-target call site compiled unchanged.

`InvalidationScope` is carried by the **command**, declared before submission, never derived from the
outcome; `MutationOutcome.forcesReSnapshot` was **deleted**. A services toggle now costs **zero**
`brew info --installed --json=v2` probes (1.27 s / 663 KB each). `MutationOutcome` gained exactly one
case, **`.noChange`** — neither success nor failure — because `brew services` exits 0 for both a state
change and a no-op.

The marker pass reads **stdout**, where `MutationOutcome`'s shipped rule is stderr-only. This was the
slice's most review-worthy decision. The containment is **structural, not conventional**:
`ServiceCommand` overrides `classify` and the protocol default is untouched, so the widening cannot
reach install or upgrade. Verify re-proved the containment independently by mutation and accepted it
as the best-defended decision in the slice.

`--all` is **unrepresentable** rather than merely forbidden: no `ServiceCommand` case omits a target.
That is the structural answer to the `upgradeAll` trap.

Absorbed defects closed: `HOMEBREW_COLOR=0` → `HOMEBREW_NO_COLOR=1` (the shipped spec mandated the
exact opposite of its own stated intent — `HOMEBREW_COLOR` is a *force-colour* boolean whose mere
presence enables ANSI); the failed-clear reason erased by the next search-driven reload; and VS2's
`pendingConfirmation` setter, closed **more strongly than asked** — it is now a computed getter with
no setter at all.

### 3.1 Deviations from plan, accepted and recorded

- **`ServicesStore` opens no `ModelContainer`**, deviating from the proposal's "joins `LocalStores`".
  Services state is launchd truth and persists nothing, so W3's one-container invariant holds *a
  fortiori*. Orchestrator-accepted.
- **The M2-2 #6 settle-grace was removed from the design (revision 2)** and stays out. See §5.
- **The poll is not a `LoopOwner` slot.** `LoopOwner.start` guards on `loops[id] == nil` and a slot
  stays claimed for the launch, so a poll registered there would run once and never restart after the
  first hide. The poll task is coordinator-owned. Orchestrator-accepted finding.
- **Spec-amendment ordering** (verify DEVIATION A, WARNING): task 18.8 ran test → fix → spec rather
  than spec → test → fix. **Not** a Strict TDD violation — RED still preceded GREEN. The spec lagged
  because the requirement gap was only *discovered* by the fix. Mitigated by the amendment being
  checked against the tests rather than back-fitted to the implementation.
- **Task 18.7's RED was obtained by mutation, not by ordering** (verify DEVIATION B). The production
  line predates the branch, so an ordering RED is *impossible*; claiming one would have been the
  dishonest option. Labelled "RED (by mutation, named)" in the artifact and reproduced independently
  by verify with an identical signature. Mutation RED is **stronger** here.
- **Task 11.1 was corrected, not merely annotated.** It originally required `;` and `$(…)` to be
  rejected at construction. They are not, and must not be: `MutationName.isSafe` is exactly
  "non-empty, no leading `-`, no whitespace", and widening the shared gate would change package
  construction rules the delta explicitly preserves. Verify judged the apply-phase override
  **correct** (ADJUDICATION 2).

### 3.2 Forecast versus outcome

Task-level forecast **~5,700–6,800** ledger lines; the design said ~3,650–5,050. The measured total
landed 4.8% above the task forecast's top — **but the totals agree by near-coincidence**, and the
honest reading is two large errors of opposite sign:

| Bucket | Forecast | Measured | Delta |
|---|---|---|---|
| SDD markdown | 1,744 (counted inside the ledger) | **474** | −1,270 — the planning markdown landed on `main` in PR #8, so it is not in this candidate |
| `Sources/` + `cellar/` | 1,870–2,100 | **2,421** | +15% to +29% |
| Tests | 1,400–1,900 | **3,956** | **2.1×–2.8× over — the real miss** |

**The reusable number**: this codebase costs **45–55 lines per test function**, not the 20–25 the
forecast used, once threat-matrix rows, mutation-verified assertions and required doc comments are
counted — and **105** tests shipped, not 70. This project has now under-priced three slices in a row
(M2-0 1.67×, M2-1 1.82×, M3-1's test bucket 2.1–2.8×). A `size:exception` was accepted before apply
(ruling #7182-1) and recorded in task 0.2; delivery strategy `exception-ok`, chain strategy
`size-exception`.

---

## 4. Register items closed

### Closed by this slice

| Item | How |
|---|---|
| **VS2** (M2-3) — `pendingConfirmation` widened to `public internal(set)` | **Closed more strongly than asked.** A nested `@Observable ConfirmationBox` holds the value; `pendingConfirmation` is a computed getter with **no setter at all**. There is no setter left to widen a second time |
| **M2-2 #7** — duplicate submission of the same command | **Closed narrowly, exactly as routed.** `ServiceSubmissionGuard`, keyed on the validated service name, on the services submit path **only**. The general dedup rule stays deferred; `brew-execution` still permits duplicate submissions in general |
| **M2-2 #9** — the sudo signature set is unprobed | **Closed as far as gate U5 reaches**: a root-domain start never invokes sudo and cannot reach a password prompt, so the shipped signature set is not on that path. The *bootstrap* signature remains, tracked separately as the U5 residual |
| **M3-0 register top item** — a failed clear's reason erased by the next search-driven reload | **Closed** (Phase 7). `HistoryStore` keeps a sticky failure reason; `reload()` ends with `sticky.map(.unavailable) ?? <fetch outcome>` instead of the unconditional `.available` |
| **Defect #7179** — `HOMEBREW_COLOR=0` | **Closed** at the source, with the spec text corrected alongside the code, plus a self-skipping integration test against a real `brew` |

### Closed by M3-0, confirmed here rather than assumed — **not by this slice**

**S1** and **W1** were listed as open on an inherited register that is **stale**. Both were verified in
shipped code at `main` before this slice planned any work for them, and **no code task exists for
either**. They are recorded as **closed by `m3-hardening-prelude` (M3-0)**, and this slice claims no
credit for them.

| Item | Evidence |
|---|---|
| **S1** — `BrewRunner.exit(of:)` fabricating `BrewExit(status: 0)` for an unknown id | `Sources/BrewProcess/BrewRunner.swift:288/293` returns `.unknownOperation`; `MutationOutcome.classify` maps it to `.launchFailed` before any prose is read. Carried in `openspec/specs/brew-execution/spec.md` |
| **W1** — a no-runner submit writing no history entry | `Sources/BrewClient/OperationCenter.swift:168-177` — the gate is opened above the runner guard and the no-runner path routes through `finish()`, the single terminal funnel, so the entry is written by construction |

---

## 5. Open follow-up register — **20 items open at close**

Merges `openspec/changes/m3-services/follow-ups.md` with the items inherited from the M3-0 archive
report. This register supersedes the M3-0 one for every item this slice touched and carries the rest
forward unchanged.

### 5.1 The one with a spec precondition

**#1 — M2-2 #6, a mutation's own post-terminal FSEvents echo. OPEN, and deliberately so.**

An earlier design draft folded this in as an `isSettling` / `settleGrace` guard on
`InstalledRefreshCoordinator`. **It was removed, and it was wrong as designed.**
`openspec/specs/installed-inventory/spec.md` requires that a change signal arriving *after* an
acquisition started MUST cause a further re-snapshot once the quiet window elapses, "so the inventory
converges on state observed at or after the newest signal". The grace guard sits exactly where that
re-snapshot fires and **drops** it. For the mutation's own echo that is harmless — but the rule cannot
distinguish the echo from a genuine external change landing in the same window, which would be
silently lost. The draft cited II10 sc5 as cover; that paragraph governs **in-flight** suppression, a
different moment and a different guarantee.

**Closing #6 requires an explicit `installed-inventory` II10 amendment** narrowing that convergence
guarantee. That is a spec decision, not a design one, and this slice did not take it. The register
already classifies the redundant re-snapshot as **conforming, not a defect**.

**Guarded rather than trusted, and both guards hold at close**: `InstalledChangeObserving.swift` is
**0 changed lines** vs `main` (`git diff main...HEAD` on that file returns empty — task 9.7,
re-measured at 17.2 and again after batch 3), and a repo scan for `isSettling|settleGrace` over
`Sources/` and `cellar/` returns **zero**.

### 5.2 Carried forward from earlier slices

| # | Item | Why open | What would close it |
|---:|---|---|---|
| 2 | **VS3** (M2-3) — app-target UI has no automated coverage | The ruling stands: accept planned manual evidence rather than stand a harness up inside a feature slice. This slice added four more untested surfaces and twelve pre-written manual checks to compensate | A dedicated XCUITest harness slice, funded separately |
| 3 | **VS4** (M2-3) — `HistoryDraft.date` is `Date()`, not an injected clock | **Considered and deliberately not adopted** (design D6). No assertion needed a deterministic timestamp; adding the seam speculatively would have been unused surface | The first assertion that genuinely needs one — then add it additively |
| 4 | **M2-2 #8** — carry `standardInput` through `ProcessSpec` | Deferred, and **no longer load-bearing**. Batch 3 made the guarantee observable without it: a real `/usr/bin/stat -f "%i %HT" /dev/fd/0` spawned through the production runner compares the **child's own reported stdin inode** against `/dev/null`, on both the `.read` and `.mutate` paths. `SystemProcess.swift` is byte-unchanged | A recording seam carrying `standardInput`, if another family ever needs one |
| 5 | **M2-2 #10** — `skippedRecordCount` is never surfaced | Deliberately **not** solved for one decoder. This slice added a fourth tolerant decoder, which strengthens the original reasoning: the answer is one mechanism across all of them | One shared "what did we skip" surface, across every tolerant decoder at once |
| 6 | **M3-0 VS2** — the equal-ordinal/equal-revision invariant is unstated | Untouched by this slice; it lives in `Catalog` | Assert it, or state it in the type |
| 7 | **M3-0 (c)** — the app-target `reconcileOrder` expression is unproved | Untouched; folds into the VS3 ruling | The VS3 harness |

### 5.3 New from this slice

| # | Item | Severity | Why open | What would close it |
|---:|---|---|---|---|
| 8 | **`InstalledMutationGate` naming debt** (verify LOW 4) | LOW | The type now serves two domains under an installed-specific name. It was always a depth counter plus a `terminals` stream with nothing installed-specific in its body, so the services gate is a second *instance*, not a second type. Renaming is public-API churn across test call sites and the composition root, and buys no behaviour | A rename in a slice already touching those call sites |
| 9 | **U5 residual** — the exact stderr/exit signature of a rejected root-domain `launchctl bootstrap` | LOW | Unprobed and not safely probeable here. The classifier degrades correctly: a rejected bootstrap is a generic failure with its log verbatim, never a success and never a state change that did not happen. A **message-quality** gap, not a correctness gap | A live probe on a machine where a root-domain service can be rejected |
| 10 | **`brew services info --json <name>` cost** | LOW | Schema-verified from Homebrew source, cost-probed only via `--all` at n = 1. A per-service call could prove slower than measured | If it does: a cache. The fetch is already lazy and selection-keyed, so the mitigation is not a redesign |
| 11 | **MEDIUM 1** — SM12 is the thinnest-covered requirement in the slice (2 UNTESTED + 1 PARTIAL of 3 scenarios) | MEDIUM | The properties hold **structurally** (`InstalledModels.swift` and `Sources/Catalog/` byte-unchanged; `ServicesStore` never reads `InstalledStore`) and the catalog-filter half is pinned by an exhaustive equality — but "structurally" is not runtime evidence and this report does not count it as such | Two tests in the existing `InstalledFilterFavoritesTests` idiom: one enumerating the installed projection's fields, one driving a deliberate name collision |
| 12 | **MEDIUM 2** — `ServiceDetailView` reports a **failed** detail probe as "No service selected" | MEDIUM | **A live user-visible defect on the branch being archived**, of the identical shape to the HIGH just fixed, with a smaller blast radius. `ServicesStore.select`'s catch binds `error` then discards it entirely (`detail = nil`) — the store has **no property that could carry it** — while `ServiceDetailView` branches on `detail != nil` only. Independently confirmed at source by verify. Genuinely more work than HIGH 1, which did not need this because `ServicesLoadState.failed` already carried its error | A projection over (`selected`, `detail`, the probe's outcome) in `ServicesPresentation`, plus a `ServiceDetailView` switch — and the store must first **keep** the failure reason |
| 13 | **MEDIUM 3** — the services list is probed once per launch and once per activation even when Services has never been shown | MEDIUM | **Not a scenario violation**: SM3 forbids *polling* while not visible and separately mandates a baseline on becoming visible, and `InstalledRefreshCoordinator` behaves the same way. But it contradicts SM3's own headline and the design's "zero cost while hidden" framing | A deliberate decision either way: gate the baseline on visibility too, or state in SM3 that a launch/activation baseline is permitted. MV-2(c) is the check that observes it |
| 14 | **MEDIUM 4** — closing one of two windows stops the poll while another window still shows Services | MEDIUM | `setVisible` is one shared boolean on an app-lifetime coordinator driven by every `ServicesListView.onDisappear`. SM3 sc3 only requires that never *more than one* loop runs, which still holds. A visibility-refcount gap, not a leak | A refcount or a per-scene identity on the coordinator's visibility input |
| 15 | **LOW 3** — the row's Copy-command control always copies `brew services start <name>` | LOW | Defensible as a default, but the label says "Copy command" without saying which one | Label it "Copy start command", or derive it from the service's current status |
| 16 | **SUGGESTION** — `ServicesListView` passes a redundant `.tag(service.id)` inside `List(_:selection:)` | SUGGESTION | Harmless; `List` already derives the tag from `Identifiable` | Delete the modifier |
| 17 | **SUGGESTION (new at verify pass 2)** — a failed refresh with a resident list surfaces nothing | SUGGESTION | The empty state renders only inside `.overlay { if services.isEmpty }`, so a refresh that fails while a previous list is resident shows a stale list with no indication. **Not a regression**: `InstalledListView.swift:79-83` has the identical shape, so it is a pre-existing **whole-app pattern**, consistent with the precedent HIGH 1 was told to follow | One decision taken across **both** domains in a later slice, not a change to this one |

### 5.4 Registered after the verify report (commit `64f6ea0`)

| # | Item | Severity | Detail |
|---:|---|---|---|
| 18 | **Package-only vocabulary in the collapsed activity bar's idle fallback** — `cellar/Activity/ActivityBar.swift:85` reads "No package changes running" | LOW | **Verified NOT a misreport.** `OperationCenterSummary.runningCommand` returns the running item's `displayCommand` for **any** family, so a live service operation does show its own argv there; the package-specific wording appears **only when nothing is running**. Stale copy, not a false statement |
| 19 | **Package-only vocabulary in the History empty/detail pane** — "Every package change Cellar made, newest first" | LOW | Same shape. Every history row renders its own subject correctly ("No package" for a null identity), so this is incomplete copy rather than a false statement about any entry |

Both are deliberately **not** fixed in M3-1: closing them is a copy change plus its tests, and it
should be taken together with any other vocabulary review when a third command family lands (taps, in
M3-2) rather than piecemeal.

### 5.5 Manual verification still owed

| # | Item | Detail |
|---:|---|---|
| 20 | **Eight deferred manual checks, owed rather than claimed** | MV-2 (a)(b)(d), MV-5 GUI half, MV-6, MV-8, MV-9, MV-10, MV-11 GUI half, MV-12. Deferred by explicit user decision after the two archive-blocking checks passed. Each corroborates a claim that already has headless proof. MV-9 additionally requires a temporary fixture patch that **must not be committed**; MV-10 must be recorded as HEADLESS-ONLY if the configured-path affordance proves unreachable — do not claim manual coverage that was not obtained (the M2-3 IH6 lesson) |

**Open follow-up count at close: 20.**

---

## 6. Probe gates

| Gate | State | Note |
|---|---|---|
| **U1, U2, U5, U6, U8** | Closed before this slice planned work | U8's marker probe and U5's privilege-path derivation are the two this slice consumed most directly; U5 leaves the bootstrap-signature residual (item 9) |
| **U3, U4** | **STILL OPEN probe gates** | Not touched by this slice — they belong to the **M3-4 cleanup** slice. Taps, cleanup and disk-usage were explicitly out of scope, and task 17.2 verified no taps, cleanup or disk-usage source file entered the candidate |

The design probed brew **6.0.14**; this slice **re-confirmed all four service markers on brew
6.0.15-4-gd610afe** during apply (see §1.2), so the classification rules are known-good across the
version bump.

---

## 7. Artifact traceability

### Engram observations

| Artifact | Observation | Topic |
|---|---:|---|
| proposal | **#7181** | `sdd/m3-services/proposal` |
| design (revision 2) | **#7183** | `sdd/m3-services/design` |
| spec | **#7184** | `sdd/m3-services/spec` |
| tasks (revision 2) | **#7186** | `sdd/m3-services/tasks` |
| verify-report (pass 2) | **#7191** | `sdd/m3-services/verify-report` |
| archive-report | *this document* | `sdd/m3-services/archive-report` |

Supporting observations referenced by the artifacts: **#7178** (probe gates), **#7179**
(`HOMEBREW_COLOR` defect), **#7180** and **#7182** (binding product rulings), **#7126** / **#7128**
(umbrella explore), **#7141** (inherited register).

### Archived files

`openspec/changes/archive/2026-08-03-m3-services/m3-services/` — proposal, design, tasks,
`specs/` (6 delta files), `follow-ups.md`, `apply-progress.md`, `verify-report.md` and
**`verify-report-pass1.md`**.

**`verify-report-pass1.md` is preserved deliberately and byte-identically**
(sha256:`8271fc5f700b99662ab79b0440f08610a154b2f196eeee053ac9ee3e440ba49b`). The FAIL pass is part of
the record: it is what found CRITICAL 1 and the two HIGHs, and discarding it would erase the evidence
that the process worked. Pass 2 bytes:
sha256:`03216ee1d2f555fbe8f4292bb364beed80dce72d3d08d9839d8b90ab08c168a7`, validator-admitted via
`gentle-ai sdd-verify-validate --requirements 22 --scenarios 93` → `{"valid":true,"verdict":"fail"}`.

Planning artifacts (proposal, design, spec deltas) already landed on `main` via **PR #8**
(merge `284aab9`); the code is on `feature/m3-services`, draft **PR #9**.

---

## 8. Cycle status

**M3-1 is complete and closed.** Planned, specced, designed, implemented under Strict TDD, verified
across two passes, remediated, manually verified on its archive-blocking subset, and promoted.

The mutation spine now carries two families with a typed, per-command invalidation scope — the
foundation **M3-2 (taps)** and **M3-4 (cleanup)** were built to consume. Gates **U3** and **U4**
remain open for M3-4.
